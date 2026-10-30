# frozen_string_literal: true

module OrderMetrics
  class UpsertService < ApplicationService
    UPFRONT_TITLE = "Payment Received Upfront"
    PREPAID_DISCOUNT_TITLE = "Prepaid Discount"
    PARTIAL_DISCOUNT_PREFIX = "Partial Payment Discount"
    WIDGET_FEE_TITLE = "COD Fee"
    ORDER_EDIT_FEE_TITLE = "COD-Fees"
    DELIVERY_BY_OUTCOME = {
      "cancelled" => "cancelled",
      "refunded" => "refunded",
      "rto" => "rto",
      "returned" => "returned",
      "delivered" => "delivered",
      "fulfilled" => "in_transit"
    }.freeze

    def initialize(shop, order, rto_order: nil)
      @shop = shop
      @order = order
      @rto_order = rto_order
    end

    def call
      return if @shop.blank? || @order["id"].blank? || @order["created_at"].blank?

      OrderMetric.upsert(build_attrs(@order["id"].to_s), unique_by: [:shop_id, :order_id])
    rescue => e
      Rails.logger.error("[OrderMetrics] upsert failed shop_id=#{@shop&.id} order_id=#{@order['id']} #{e.class}: #{e.message}")
      nil
    end

    private

    def build_attrs(order_id)
      notes = note_attributes
      tags = order_tags
      confirmation = OrderConfirmation.where(shop_id: @shop.id, order_id: order_id).select(:id, :status, :draft_order_id).first
      ordered_at = Time.zone.parse(@order["created_at"].to_s)
      total = money(@order["current_total_price"].presence || @order["total_price"])
      applications = discount_applications
      upfront_discount = sum_amount(applications.select { |a| a[:title].to_s.include?(UPFRONT_TITLE) })
      merchant_discounts = applications.reject { |a| a[:title].to_s.include?(UPFRONT_TITLE) || a[:amount].zero? }
      is_partial = tags.include?("Partial-Payment-Received") ||
        (confirmation&.status == "COD-Partial-Payment-Received" && confirmation.draft_order_id.blank?)
      partial_upfront = if !is_partial then 0.to_d
                        elsif upfront_discount.positive? then upfront_discount
                        else paid_amount(total)
                        end
      cod_fee, cod_fee_source = cod_fee_with_source(notes)
      session_id = notes["_codkSessionId"].presence
      is_converted = tags.include?("Prepaid-From-COD")
      converted_from_id = is_converted ? converted_from(order_id) : nil
      upsell_items, upsell_revenue = upsell_totals
      free_gift_items, free_gift_value, free_gift_rule_ids = free_gift_totals

      attrs = {
        shop_id: @shop.id,
        order_id: order_id,
        order_confirmation_id: confirmation&.id,
        order_name: @order["name"],
        ordered_at: ordered_at,
        currency: @order["currency"],
        is_cod: OrderConfirmation.new(shop: @shop).is_cod(@order),
        total_price: total,
        original_total: total + upfront_discount,
        discount_total: sum_amount(merchant_discounts),
        discounts: merchant_discounts.map { |a| { code: a[:code] || a[:title], type: a[:type], amount: a[:amount].to_s } },
        prepaid_discount: prepaid_discount(merchant_discounts, notes, is_converted, converted_from_id),
        cod_fee: cod_fee,
        cod_fee_source: cod_fee_source,
        is_partial: is_partial,
        partial_upfront: partial_upfront,
        is_converted_prepaid: is_converted,
        converted_from_order_id: converted_from_id,
        is_otp_verified: notes["_otpVerifiedPhoneNumber"].present?,
        is_cod_form: @order["source_name"] == "codking_form" || notes["_codkFormSessionId"].present?,
        is_ac_recovered: ac_recovered?(session_id, notes),
        widget_session_id: session_id,
        upsell_items: upsell_items,
        upsell_revenue: upsell_revenue,
        free_gift_items: free_gift_items,
        free_gift_value: free_gift_value,
        free_gift_rule_ids: free_gift_rule_ids
      }
      attrs.merge!(delivery_attrs) if @rto_order
      attrs
    end

    def note_attributes
      Array(@order["note_attributes"]).each_with_object({}) do |attr, h|
        h[attr["name"].to_s] = attr["value"].to_s
      end
    end

    def order_tags
      tags = @order["tags"]
      tags.is_a?(Array) ? tags : tags.to_s.split(",").map(&:strip)
    end

    def discount_applications
      amounts = Hash.new(0.to_d)
      (Array(@order["line_items"]) + Array(@order["shipping_lines"])).each do |line|
        next if line["current_quantity"] == 0

        Array(line["discount_allocations"]).each do |alloc|
          amounts[alloc["discount_application_index"].to_i] += money(alloc["amount"])
        end
      end
      Array(@order["discount_applications"]).each_with_index.map do |app, i|
        { code: app["code"], title: app["title"] || app["description"], type: app["type"], amount: amounts[i] }
      end
    end

    def prepaid_discount(applications, notes, is_converted, converted_from_id)
      claimed_amount, claimed_code = notes["_codkPrepaidDiscount"].to_s.split("|", 2)
      claimed = money(claimed_amount)

      if is_converted
        applied = sum_amount(applications.select { |a| a[:title] == PREPAID_DISCOUNT_TITLE })
        return [claimed, applied].min if claimed.positive?

        return [applied - original_discount_total(converted_from_id), 0.to_d].max
      end

      return 0.to_d unless notes["_codkAmountType"] == "percentage" && notes["_codkAmountValue"].to_f == 100

      if claimed.positive? && claimed_code.present?
        applied = sum_amount(applications.select { |a| code_matches?(a, claimed_code) })
        return [claimed, applied].min
      end

      codes = PartialRuleSet.where(shop_id: @shop.id, amount_type: "percentage", amount: 100)
                            .where.not(discount_code: [nil, ""]).pluck(:discount_code)
      sum_amount(applications.select do |a|
        a[:title].to_s.start_with?(PARTIAL_DISCOUNT_PREFIX) || codes.any? { |code| code_matches?(a, code) }
      end)
    end

    def code_matches?(application, code)
      application[:code].to_s.casecmp?(code.strip) || application[:title].to_s.casecmp?(code.strip)
    end

    def original_discount_total(order_id)
      return 0.to_d if order_id.blank?

      OrderMetric.where(shop_id: @shop.id, order_id: order_id.to_s).pick(:discount_total) || 0.to_d
    end

    def cod_fee_with_source(notes)
      form_fee = money(notes["_codkCodFee"])
      return [form_fee, "cod_form"] if form_fee.positive?

      edit_fee = Array(@order["line_items"]).select { |li| li["title"] == ORDER_EDIT_FEE_TITLE }.sum do |li|
        money(li["price"]) * (li["current_quantity"] || li["quantity"]).to_i
      end
      return [edit_fee, "order_edit"] if edit_fee.positive?

      keyword = @shop.setting&.enable_shipping_cod_fees ? @shop.setting.cod_fee_shipping_keyword.to_s.downcase.presence : nil
      Array(@order["shipping_lines"]).each do |line|
        title = line["title"].to_s
        price = money(line["price"])
        next unless price.positive?
        return [price, "widget"] if title.include?(WIDGET_FEE_TITLE)
        return [price, "shipping_rate"] if keyword && title.downcase.include?(keyword)
      end
      [0.to_d, nil]
    end

    def paid_amount(total)
      return 0.to_d if @order["total_outstanding"].nil?

      [total - money(@order["total_outstanding"]), 0.to_d].max
    end

    def converted_from(order_id)
      OrderConfirmation.where(shop_id: @shop.id, draft_order_id: order_id, status: "COD-Prepaid").pick(:order_id)
    end

    def ac_recovered?(session_id, notes)
      ids = [@order["checkout_id"].presence&.to_s, session_id]
      ids << "codf_#{notes['_codkFormSessionId']}" if notes["_codkFormSessionId"].present?
      ids += PreOrderOtp.where(shop_id: @shop.id, device_id: session_id).pluck(:id).map { |id| "otp_#{id}" } if session_id
      ids.compact!
      return false if ids.empty?

      AbandonedCart.where(shop_id: @shop.id, checkout_id: ids).where("LOWER(notes) = 'recovered'").exists?
    end

    def upsell_totals
      Array(@order["line_items"]).each_with_object([0, 0.to_d]) do |line, totals|
        next unless Array(line["properties"]).any? { |prop| prop["name"] == Upsells::LINE_PROPERTY && prop["value"].to_s == "true" }

        quantity = (line["current_quantity"] || line["quantity"]).to_i
        next unless quantity.positive?

        discount = Array(line["discount_allocations"]).sum(0.to_d) { |a| money(a["amount"]) }
        totals[0] += quantity
        totals[1] += [money(line["price"]) * quantity - discount, 0.to_d].max
      end
    end

    def free_gift_totals
      Array(@order["line_items"]).each_with_object([0, 0.to_d, []]) do |line, totals|
        prop = Array(line["properties"]).find { |p| p["name"] == FreeGifts::LINE_PROPERTY && p["value"].present? }
        next unless prop

        quantity = (line["current_quantity"] || line["quantity"]).to_i
        next unless quantity.positive?

        totals[0] += quantity
        totals[1] += money(line["price"]) * quantity
        totals[2] |= [prop["value"].to_s]
      end
    end

    def delivery_attrs
      {
        delivery_status: DELIVERY_BY_OUTCOME.fetch(@rto_order.outcome_status.to_s, "unfulfilled"),
        delivered_at: @rto_order.delivered_at,
        rto_at: @rto_order.rto_at
      }
    end

    def sum_amount(applications)
      applications.sum(0.to_d) { |a| a[:amount] }
    end

    def money(value)
      value.to_s.to_d
    end
  end
end

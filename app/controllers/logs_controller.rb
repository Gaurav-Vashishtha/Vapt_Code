require "csv"

class LogsController < AuthenticatedController
  def index
    type = params[:type] || "twilio_log"
    logs_scope = filtered_logs_scope(type)

    paginated = logs_scope.page(params[:page]).per(25)
    total_charge = logs_scope.unscope(:order).sum(:actual_charge_applied)

    render json: {
      data: paginated.map { |log| format_log(log, type) },
      total_actual_charge: total_charge.to_f,
      pagy: {
        page: paginated.current_page,
        pages: paginated.total_pages,
        last: paginated.total_pages
      }
    }
  end

  def export
    type = params[:type] || "twilio_log"
    logs_scope = filtered_logs_scope(type)

    csv_string = CSV.generate(headers: true) do |csv|
      csv << export_headers(type)
      logs_scope.find_each(batch_size: 500, order: :desc) do |log|
        csv << export_row(log, type)
      end
    end

    send_data(
      csv_string,
      filename: "usage-logs-#{type.tr('_', '-')}-#{Time.current.strftime('%Y%m%d-%H%M%S')}.csv",
      type: "text/csv"
    )
  end

  private

  def filtered_logs_scope(type)
    query = params[:query].to_s.strip
    days = params[:days].to_i
    shop_id = @shop&.id || params[:shopId]
    from_date = days.days.ago.beginning_of_day

    case type
    when "twilio_log"
      TwilioLog.includes(:order_confirmation)
               .where(shop_id: shop_id)
               .where("twilio_logs.created_at >= ?", from_date)
               .yield_self { |scope| query.present? ? scope.where("customer_number ILIKE ?", "%#{query}%") : scope }
               .order("twilio_logs.created_at DESC")
    when "pre_order_otp"
      PreOrderOtp.otp_sends.where(shop_id: shop_id)
                 .where("created_at >= ?", from_date)
                 .yield_self { |scope| query.present? ? scope.where("phone ILIKE ?", "%#{query}%") : scope }
                 .order(created_at: :desc)
    when "abandoned_cart"
      AbandonedCart.where(shop_id: shop_id)
                   .where("created_at >= ?", from_date)
                   .yield_self { |scope| query.present? ? scope.where("phone ILIKE ?", "%#{query}%") : scope }
                   .order(created_at: :desc)
    else
      TwilioLog.none
    end
  end

  def export_headers(type)
    identifier =
      case type
      when "twilio_log" then "Order Number"
      when "pre_order_otp" then "Device ID"
      when "abandoned_cart" then "Checkout ID"
      else "Identifier"
      end

    ["Date", identifier, "Phone", "Type", "Status", "Charge"]
  end

  def export_row(log, type)
    case type
    when "twilio_log"
      [
        log.created_at&.iso8601,
        log.order_confirmation&.order_number,
        log.customer_number,
        log.ver_type.presence || "SMS",
        log.status,
        log.actual_charge_applied.to_f
      ]
    when "pre_order_otp"
      [
        log.created_at&.iso8601,
        log.device_id,
        log.phone,
        "Pre-order OTP",
        log.status,
        log.actual_charge_applied.to_f
      ]
    when "abandoned_cart"
      [
        log.created_at&.iso8601,
        log.checkout_id,
        log.phone,
        log.notif_type.presence || "Abandoned Cart",
        log.status,
        log.actual_charge_applied.to_f
      ]
    else
      []
    end
  end

  def format_log(log, type)
    base = {
      id: log.id,
      created_at: log.created_at&.iso8601 || "-",
      status: log.status || "-",
      actual_charge_applied: log.actual_charge_applied.to_f,
    }

    case type
    when "twilio_log"
      base.merge({
        customer_number: log.customer_number || "-",
        ver_type: log.ver_type || "-",
        order_confirmation: {
          order_number: log.order_confirmation&.order_number || "-"
        }
      })
    when "pre_order_otp"
      base.merge({
        phone: log.phone || "-",
        device_id: log.device_id || "-"
      })
    when "abandoned_cart"
      base.merge({
        phone: log.phone || "-",
        checkout_id: log.checkout_id || "-",
        notif_type: log.notif_type || "-"
      })
    else
      base
    end
  end
end

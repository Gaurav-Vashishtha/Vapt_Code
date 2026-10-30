# frozen_string_literal: true

# Reads a PreOrderOtp cart_details array into [{variant_id:, quantity:}], resolving
# partial-payment variants back to the original product variant.
# Shared by the abandoned-cart permalink (NetworkJobs::PreOrderOtpCartScheduleJob)
# and the draft-order sync (PreOrderOtpDraftJobs::SyncJob).
module PreOrderOtpCart
  module_function

  def line_items(cart_details)
    Array(cart_details).filter_map do |item|
      next if item.blank?

      variant_id = item["variant_id"] || item["variantId"]
      # OTP send stores variant_id/quantity; later cart syncs (update_cart_details) overwrite it
      # with variantId/totalQuantity.
      quantity = item["quantity"] || item["qty"] || item["totalQuantity"]
      next if variant_id.blank? || quantity.blank?

      { variant_id: original_variant_id(variant_id), quantity: quantity }
    end
  end

  # Same cart (variants + quantities, any order) => same fingerprint.
  def fingerprint(line_items)
    merged = line_items.each_with_object(Hash.new(0)) { |li, acc| acc[li[:variant_id].to_s] += li[:quantity].to_i }
    Digest::SHA256.hexdigest(merged.sort.map { |v, q| "#{v}:#{q}" }.join(","))
  end

  def original_variant_id(variant_id)
    mapping = PartialProductMapping.find_by(partial_variant_id: variant_id)
    original = mapping&.original_variant_ids&.first
    original.present? ? original.split(":")[0] : variant_id
  end
end

# frozen_string_literal: true

module Churn
  # One place for "which COD King features did this store have on".
  # Used by UninstallNewJob (snapshot) and the churn dashboard (labels).
  module FeatureSet
    # uninstalled_shops boolean column => label
    SNAPSHOT_COLUMNS = {
      sms: 'SMS',
      confirmation_sms_enabled: 'Confirmation SMS',
      cod_fee_enabled: 'COD fee',
      enable_pre_order_otp: 'Pre-order OTP',
      abandoned_cart_enabled: 'Abandoned cart',
      prepaid_enabled: 'COD → Prepaid',
      partial_payment_enabled: 'Partial payment',
      ac_whatsapp: 'AC WhatsApp',
      bsp_integrated: 'WhatsApp BSP',
      cod_show_hide_enabled: 'COD show/hide'
    }.freeze

    # Extra settings flags kept in uninstalled_shops.feature_snapshot (jsonb)
    EXTRA_SETTINGS = {
      confirmation_whatsapp: 'WhatsApp confirmation',
      fulfilment_whatsapp: 'WhatsApp fulfilment',
      first_purchase_whatsapp_enabled: 'First-purchase WhatsApp',
      enable_fulfilment_message: 'Fulfilment message',
      ivr: 'IVR',
      cod_form_enabled: 'COD form',
      pixel_enabled: 'Meta pixel'
    }.freeze

    module_function

    # Hash of every flag for a live shop (for the uninstall snapshot).
    def snapshot_for(shop)
      setting = shop.setting
      base = {
        sms: setting&.sms,
        confirmation_sms_enabled: setting&.confirmation_sms_enabled,
        cod_fee_enabled: (setting&.cod_fee_enabled || setting&.enable_shipping_cod_fees),
        enable_pre_order_otp: setting&.enable_pre_order_otp,
        abandoned_cart_enabled: setting&.abandoned_cart_enabled,
        prepaid_enabled: setting&.prepaid_enabled,
        partial_payment_enabled: setting&.partial_payment_enabled,
        ac_whatsapp: setting&.ac_whatsapp,
        bsp_integrated: shop.respond_to?(:whatsapp_account) ? shop.whatsapp_account.present? : false,
        cod_show_hide_enabled: setting.respond_to?(:is_cod_show_hide_enabled?) ? setting.is_cod_show_hide_enabled? : false
      }
      extra = EXTRA_SETTINGS.keys.index_with { |k| setting.respond_to?(k) ? setting.public_send(k) : nil }
      base.merge(extra).transform_values { |v| v == true }
    rescue => e
      Rails.logger.warn("[Churn::FeatureSet] snapshot failed for #{shop&.shopify_domain}: #{e.message}")
      {}
    end

    def labels_for_shop(shop)
      labels_from_hash(snapshot_for(shop))
    end

    def labels_for_uninstalled(row)
      flags = SNAPSHOT_COLUMNS.keys.index_with { |k| row.public_send(k) == true }
      snapshot = row.respond_to?(:feature_snapshot) ? (row.feature_snapshot || {}) : {}
      snapshot.each { |k, v| flags[k.to_sym] ||= (v == true) }
      labels_from_hash(flags)
    end

    def labels_from_hash(flags)
      all = SNAPSHOT_COLUMNS.merge(EXTRA_SETTINGS)
      flags.select { |_, on| on }.keys.filter_map { |k| all[k.to_sym] }
    end
  end
end

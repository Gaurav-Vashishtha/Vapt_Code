# frozen_string_literal: true

# COD Form module (docs/cod-form/ARCHITECTURE.md).

# The adapters live in app/services/cod_form/adapters/ but are named CodForm::RulesAdapter,
# CodForm::CodFeeAdapter, CodForm::PartialRulesAdapter and CodForm::MoneyFormatAdapter
# (ARCHITECTURE.md F.1 / K.9): the directory is a plain folder, not a namespace.
Rails.autoloaders.main.collapse(Rails.root.join("app/services/cod_form/adapters").to_s)

# F.2: 12 s read time-out for the Admin GraphQL calls the form makes while a buyer waits. The
# hook only acts inside CodFormShopifyTimeout.with { … }; every other caller of the shared
# ShopifyAPI::GraphQL client keeps Net::HTTP's defaults.
require Rails.root.join("lib/cod_form_shopify_timeout").to_s
Rails.application.config.after_initialize do
  installed = defined?(ShopifyAPI::GraphQL::HTTPClient) && CodFormShopifyTimeout.install!(ShopifyAPI::GraphQL::HTTPClient)
  Rails.logger.warn("[CodForm] Shopify GraphQL time-out hook not installed (client class changed?)") unless installed
rescue StandardError => e
  Rails.logger.warn("[CodForm] Shopify GraphQL time-out hook failed: #{e.class}")
end

Rails.application.config.to_prepare do
  # The storefront metafield mirrors the Limit COD rules and the COD fee (C.1). When one of
  # those Setting columns changes, re-sync the metafield of shops that use the form.
  # Registered here so app/models/setting.rb itself is not edited; the flag keeps a code
  # reload (development) from registering the callback twice on the same class object.
  unless Setting.instance_variable_get(:@cod_form_metafield_hook)
    Setting.instance_variable_set(:@cod_form_metafield_hook, true)
    Setting.after_commit(on: %i[create update]) do
      begin
        watched = CodForm::RulesAdapter::WATCHED_COLUMNS + CodForm::CodFeeAdapter::WATCHED_COLUMNS
        if (saved_changes.keys & watched).any? && shop_id.present? &&
           CodForm::ShopConfig.where(shop_id: shop_id).cod_form_mode.exists?
          CodForm::MetafieldSyncJob.perform_async(shop_id)
        end
      rescue StandardError => e
        # Never let the form module break a settings save.
        Rails.logger.warn("[CodForm] metafield re-sync hook failed setting_id=#{id} #{e.class}")
      end
    end
  end
end

# ENV validation: warn, never abort the boot (the rest of the app does not depend on these).
Rails.application.config.after_initialize do
  next unless Rails.env.production?

  {
    "APP_HOST" => "API base of the storefront form (codk.cod_form metafield `api`)",
    "COD_FORM_EXTENSION_UUID" => "theme app extension id: embed deep link and asset_base check"
  }.each do |name, purpose|
    Rails.logger.warn("[CodForm] ENV #{name} is not set (#{purpose})") if ENV[name].to_s.strip.empty?
  end

  if ENV["COD_FORM_ORIGIN_ENFORCE"].to_s == "false"
    Rails.logger.warn("[CodForm] COD_FORM_ORIGIN_ENFORCE=false: the storefront API origin check only logs")
  end
  if ENV["COD_FORM_ALLOW_LOCALHOST"].to_s == "true"
    Rails.logger.warn("[CodForm] COD_FORM_ALLOW_LOCALHOST=true: localhost origins are accepted by the storefront API")
  end
end

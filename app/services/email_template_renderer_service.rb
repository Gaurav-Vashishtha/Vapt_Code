# frozen_string_literal: true

# Renders email template subject/body with variables from shop/setting or uninstalled_shop.
# Variables: {{shop.column}}, {{setting.column}}, or {{uninstalled_shop.column}}
module EmailTemplateRendererService
  module_function

  def render_subject(template, shop: nil, uninstalled_shop: nil)
    render_string(template.subject, shop: shop, uninstalled_shop: uninstalled_shop)
  end

  def render_body(template, shop: nil, uninstalled_shop: nil)
    render_string(template.body, shop: shop, uninstalled_shop: uninstalled_shop)
  end

  def render_string(str, shop: nil, uninstalled_shop: nil)
    return str if str.blank?
    result = str.dup
    if shop
      { "shop" => shop, "setting" => shop.setting }.each do |prefix, record|
        next unless record
        record.attributes.each do |key, value|
          result.gsub!("{{#{prefix}.#{key}}}", value.to_s) if result.include?("{{#{prefix}.#{key}}}")
        end
      end
    end
    if uninstalled_shop
      uninstalled_shop.attributes.each do |key, value|
        result.gsub!("{{uninstalled_shop.#{key}}}", value.to_s) if result.include?("{{uninstalled_shop.#{key}}}")
      end
    end
    result
  end
end

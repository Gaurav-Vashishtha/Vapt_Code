# frozen_string_literal: true

# Merchant notices of the COD Form module (ARCHITECTURE.md I.6).
#   CodFormMailer.usage_notice(shop_id, level)         level: 50 | 80 | 100   (CAP-8)
#   CodFormMailer.otp_unavailable_notice(shop_id)      (product decision 15)
# Both take ids so they can be enqueued; they send nothing when the shop has no owner email.
# Strings live in config/locales/en.yml under cod_form_mailer.
class CodFormMailer < ApplicationMailer
  layout "mailer"

  def usage_notice(shop_id, level)
    @shop = Shop.find_by(id: shop_id)
    return if @shop.nil? || @shop.owner_email.blank?

    state = CodForm::CapService.state(@shop, fresh: true)
    @level = level.to_i >= 100 ? 100 : (level.to_i >= 80 ? 80 : 50)
    @orders = state["orders"].to_i
    @cap = state["cap"].to_i
    @grace_orders = state["grace_orders"].to_i
    @behaviour = state["behaviour"].to_s
    @percent = state["percent"].to_i
    @owner = @shop.owner_name.presence || I18n.t("cod_form_mailer.common.there")
    @shop_name = @shop.shopify_domain
    @admin_url = admin_url(@shop)
    @body_key = usage_body_key(@level, @behaviour, @grace_orders)
    @paid = @shop.charge_id.present?

    subject_key = @level == 100 ? "subject_100" : "subject_80"
    mail(to: @shop.owner_email, subject: I18n.t("cod_form_mailer.usage_notice.#{subject_key}", cap: @cap, percent: @percent))
  end

  def otp_unavailable_notice(shop_id)
    @shop = Shop.find_by(id: shop_id)
    return if @shop.nil? || @shop.owner_email.blank?

    @count = [
      FormFunnelEvent.where(shop_id: @shop.id, event_type: "cf_otp_bypassed", occurred_at: 24.hours.ago..Time.current).count,
      1
    ].max
    @owner = @shop.owner_name.presence || I18n.t("cod_form_mailer.common.there")
    @shop_name = @shop.shopify_domain
    @admin_url = admin_url(@shop)

    mail(to: @shop.owner_email, subject: I18n.t("cod_form_mailer.otp_unavailable_notice.subject"))
  end

  private

  def admin_url(shop)
    "https://#{shop.shopify_domain}/admin/apps"
  end

  # Which paragraph explains what happens next (J.2 states).
  def usage_body_key(level, behaviour, grace_orders)
    case behaviour
    when "flag_only" then level == 100 ? "full_flag_only" : "warn_flag_only"
    when "grace"
      if level == 100
        grace_orders.positive? ? "full_grace" : "full_fallback"
      else
        grace_orders.positive? ? "warn_grace" : "warn_fallback"
      end
    else level == 100 ? "full_fallback" : "warn_fallback"
    end
  end
end

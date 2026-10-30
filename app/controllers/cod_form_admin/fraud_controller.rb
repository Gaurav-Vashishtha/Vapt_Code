# frozen_string_literal: true

module CodFormAdmin
  # Fraud protection screen (D.15): cod_form_shop_configs.fraud (B.1.2) plus the OTP mode and RTO
  # gating parts of `general`. OTP in the form is switched on here (`otp.enabled`); the channel and templates stay
  # on the existing OTP screen (`shop_otp_enabled` is the store-wide switch, read-only here).
  class FraudController < BaseController
    def show
      render json: fraud_payload
    end

    # PUT /cod_form/fraud  {"fraud": {…}, "otp": {…}, "rto": {…}} (each optional, partial)
    def update
      old_fraud = Validators::Fraud.complete(@config.fraud, engine_default(:fraud))
      old_general = Validators::General.complete(@config.general, engine_default(:general))

      fraud = old_fraud
      if body.key?("fraud")
        fraud = validated!(Validators::Fraud.normalize(body_hash("fraud"), current: @config.fraud, engine_defaults: engine_default(:fraud)))
        gate!("velocity_limits") if Validators::Fraud.enables_limit?(old_fraud, fraud)
      end

      general = old_general
      patch = {}
      patch["otp"] = body_hash("otp") if body.key?("otp")
      patch["rto"] = body_hash("rto") if body.key?("rto")
      if patch.any?
        result = Validators::General.normalize(patch.compact, current: @config.general, engine_defaults: engine_default(:general))
        # Report under the keys of this endpoint ("otp.mode"), not "general.otp.mode".
        errors = result["errors"].transform_keys { |key| key.sub(/\Ageneral\./, "") }
        raise ValidationError.new(errors) if errors.any?

        general = result["value"]
        Validators::General.gated_features(old_general, general).each { |feature| gate!(feature) }
      end

      if fraud != @config.fraud || general != @config.general
        @config.update!(fraud: fraud, general: general)
        audit_changes("fraud", old_fraud, fraud)
        audit_changes("general", old_general, general)
        bump!
      end
      render json: fraud_payload
    end

    private

    def fraud_payload
      general = Validators::General.complete(@config.general, engine_default(:general))
      setting = @shop.setting
      {
        "fraud" => Validators::Fraud.complete(@config.fraud, engine_default(:fraud)),
        "otp" => general["otp"],
        "rto" => general["rto"],
        "shop_otp_enabled" => setting.present? && setting.enable_pre_order_otp == true,
        # What the form does today: its own switch (general.otp.enabled).
        "otp_enabled" => CodForm::OtpService.on?(setting, general)
      }
    end
  end
end

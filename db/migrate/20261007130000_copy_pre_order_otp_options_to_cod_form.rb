# frozen_string_literal: true

# COD Form: the form's OTP channel, number of sends and resend wait become its own settings
# (cod_form_shop_configs.general.otp.whatsapp / max_attempts / resend_wait_seconds) instead of
# being read from the pre-order OTP screen. Shops already using the form keep what they have
# today: the three values are copied over once, where the form has none of its own.
class CopyPreOrderOtpOptionsToCodForm < ActiveRecord::Migration[7.2]
  def up
    execute <<~SQL.squish
      UPDATE cod_form_shop_configs c
      SET general = jsonb_set(
            c.general, '{otp}',
            jsonb_build_object(
              'whatsapp', COALESCE(s.pre_whatsapp_button, false),
              'max_attempts', LEAST(GREATEST(COALESCE(s.max_retries, 3), 1), 5),
              'resend_wait_seconds', LEAST(GREATEST(COALESCE(NULLIF(s.otp_wait_time, 0), 30), 15), 300)
            ) || COALESCE(c.general->'otp', '{}'::jsonb),
            true),
          updated_at = NOW()
      FROM settings s
      WHERE s.shop_id = c.shop_id
        AND c.storefront_mode = 'cod_form'
    SQL
  end

  def down
    # Not reversible: a copied value cannot be told apart from one the merchant chose.
  end
end

# frozen_string_literal: true

# COD Form: OTP in the form gets a flag of its own (cod_form_shop_configs.general.otp.enabled)
# instead of following the store-wide pre-order OTP switch. Shops that already use the form
# and never chose a value keep what they have today: the pre-order OTP flag is copied over.
class CopyPreOrderOtpToCodForm < ActiveRecord::Migration[7.2]
  def up
    execute <<~SQL.squish
      UPDATE cod_form_shop_configs c
      SET general = jsonb_set(
            jsonb_set(c.general, '{otp}', COALESCE(c.general->'otp', '{}'::jsonb), true),
            '{otp,enabled}',
            to_jsonb(COALESCE((SELECT s.enable_pre_order_otp FROM settings s WHERE s.shop_id = c.shop_id ORDER BY s.id LIMIT 1), false)),
            true),
          updated_at = NOW()
      WHERE c.storefront_mode = 'cod_form'
        AND (c.general->'otp'->'enabled') IS NULL
    SQL
  end

  def down
    # Not reversible: the copied value cannot be told apart from one the merchant chose.
  end
end

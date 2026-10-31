# frozen_string_literal: true

class OpsDynamicChargeDaily < ApplicationRecord
  self.table_name = 'ops_dynamic_charge_dailies'

  SOURCES = %i[sms whatsapp whatsapp_bsp preorder abandoned_sms abandoned_whatsapp ivr prepaid partial_payment].freeze
end

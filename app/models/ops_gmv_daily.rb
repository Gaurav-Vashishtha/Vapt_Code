# frozen_string_literal: true

# Daily GMV rollup row (IST day x currency x COD/prepaid). See Ops::GmvRollup.
class OpsGmvDaily < ApplicationRecord
  self.table_name = 'ops_gmv_dailies'
end

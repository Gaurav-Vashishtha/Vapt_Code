# frozen_string_literal: true

# The PIN / postal code lookup (COD Form state prefill, order confirmations, zipcode refresh)
# reads `locations` by zipcode + country. Without an index every lookup scans the table.
class AddZipcodeIndexToLocations < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :locations, %i[zipcode country], algorithm: :concurrently, if_not_exists: true
  end
end

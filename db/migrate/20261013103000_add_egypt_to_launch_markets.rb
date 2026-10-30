# frozen_string_literal: true

# Adds Egypt (EG) to the "Launch markets" COD Form country group, whose shops get unlimited
# COD Form orders on every plan (PM_DECISIONS.md Q8). The group was seeded by
# SeedCodFormDefaults; codes added in the internal admin are kept. Uses a migration-local model.
class AddEgyptToLaunchMarkets < ActiveRecord::Migration[7.2]
  class LaunchCountryGroup < ActiveRecord::Base
    self.table_name = "cod_form_country_groups"
  end

  GROUP_NAME = "Launch markets"
  CODE = "EG"

  def up
    group = LaunchCountryGroup.find_by(name: GROUP_NAME)
    unless group
      say "#{GROUP_NAME} group not found; nothing to change"
      return
    end

    codes = Array(group.country_codes)
    group.update_columns(country_codes: codes + [CODE], updated_at: Time.current) unless codes.include?(CODE)
  end

  def down
    group = LaunchCountryGroup.find_by(name: GROUP_NAME)
    return unless group

    group.update_columns(country_codes: Array(group.country_codes) - [CODE], updated_at: Time.current)
  end
end

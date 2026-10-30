# frozen_string_literal: true

class AddBspPrepaidTemplateIdToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :bsp_prepaid_template_id, :bigint
  end
end

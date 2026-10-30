class AddPartialExpandFlowEnabledToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :partial_expand_flow_enabled, :boolean, default: false, null: false
  end
end

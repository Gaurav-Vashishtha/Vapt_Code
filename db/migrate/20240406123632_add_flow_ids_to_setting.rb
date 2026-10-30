class AddFlowIdsToSetting < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :retry_flow_id, :string, default:''
    add_column :settings, :cancel_flow_id, :string, default:''
    add_column :settings, :ac_flow_id, :string, default:''
  end
end

class AddFulfilmentFlowIdToSetting < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :fulfilment_flow_id, :string, default:''
  end
end

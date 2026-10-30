class EnableFulfillmentMessageToSettings < ActiveRecord::Migration[6.0]
  def change
     add_column :settings, :enable_fulfilment_message, :boolean, default:false
     add_column :settings, :fulfilment_template, :string, default:''
  end
end

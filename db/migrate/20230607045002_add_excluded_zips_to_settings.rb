class AddExcludedZipsToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :excluded_zips, :string , default:''
  end
end

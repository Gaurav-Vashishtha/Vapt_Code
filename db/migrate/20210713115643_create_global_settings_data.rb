class CreateGlobalSettingsData < ActiveRecord::Migration[6.0]
  def self.up
    GlobalSetting.create({
      cod_include_tags: 'cash,cod,bogus,manual,bank',
      cod_exclude_tags: 'gcash_via_paymongo'
    })
  end

  def self.down
    GlobalSetting.delete_all
  end
end

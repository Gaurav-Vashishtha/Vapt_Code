class AddExcludeIncludeToShops < ActiveRecord::Migration[6.0]
  def up
    add_column :shops, :cod_include_tags, :text
    add_column :shops, :cod_exclude_tags, :text
    Shop.update(
      cod_include_tags: GlobalSetting.first.cod_include_tags,
      cod_exclude_tags: GlobalSetting.first.cod_exclude_tags,
    )
  end

  def down
    remove_column :shops, :cod_include_tags, :text
    remove_column :shops, :cod_exclude_tags, :text
  end
end

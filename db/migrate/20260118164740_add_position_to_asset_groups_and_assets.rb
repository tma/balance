class AddPositionToAssetGroupsAndAssets < ActiveRecord::Migration[8.1]
  def change
    add_column :asset_groups, :position, :integer, default: 0
    add_column :assets, :position, :integer, default: 0
  end
end

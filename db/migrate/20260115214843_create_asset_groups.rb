class CreateAssetGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :asset_groups do |t|
      t.string :name, null: false
      t.text :description

      t.timestamps
    end

    # Add as nullable first to handle existing assets
    add_reference :assets, :asset_group, null: true, foreign_key: true

    # For existing assets, create a default group and assign them
    reversible do |dir|
      dir.up do
        if Asset.any?
          default_group = AssetGroup.create!(name: "Uncategorized")
          Asset.where(asset_group_id: nil).update_all(asset_group_id: default_group.id)
        end
      end
    end

    # Now make it NOT NULL
    change_column_null :assets, :asset_group_id, false
  end
end

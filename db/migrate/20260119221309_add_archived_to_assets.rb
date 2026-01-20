class AddArchivedToAssets < ActiveRecord::Migration[8.1]
  def change
    add_column :assets, :archived, :boolean, default: false, null: false
    add_index :assets, :archived
  end
end

class CreateAssetTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :asset_types do |t|
      t.string :name
      t.boolean :is_liability

      t.timestamps
    end
  end
end

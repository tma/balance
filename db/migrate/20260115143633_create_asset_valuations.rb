class CreateAssetValuations < ActiveRecord::Migration[8.1]
  def change
    create_table :asset_valuations do |t|
      t.references :asset, null: false, foreign_key: true
      t.decimal :value
      t.date :date

      t.timestamps
    end
  end
end

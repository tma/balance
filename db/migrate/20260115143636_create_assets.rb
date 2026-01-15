class CreateAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :assets do |t|
      t.string :name
      t.references :asset_type, null: false, foreign_key: true
      t.decimal :value
      t.string :currency
      t.text :notes

      t.timestamps
    end
  end
end

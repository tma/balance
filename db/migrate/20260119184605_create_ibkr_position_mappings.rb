class CreateIbkrPositionMappings < ActiveRecord::Migration[8.1]
  def change
    create_table :ibkr_position_mappings do |t|
      t.references :ibkr_connection, null: false, foreign_key: true
      t.string :symbol, null: false
      t.string :description
      t.references :asset, foreign_key: true  # Nullable - unmapped positions have no asset
      t.decimal :last_quantity
      t.decimal :last_value
      t.string :currency
      t.datetime :last_synced_at

      t.timestamps
    end

    add_index :ibkr_position_mappings, [ :ibkr_connection_id, :symbol ], unique: true
  end
end

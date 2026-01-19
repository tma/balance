class RenameBrokerTables < ActiveRecord::Migration[8.1]
  def change
    # Rename tables (SQLite automatically renames indexes with the table)
    rename_table :ibkr_connections, :broker_connections
    rename_table :ibkr_position_mappings, :broker_positions

    # Add broker_type enum to broker_connections
    add_column :broker_connections, :broker_type, :integer, default: 0, null: false

    # Rename foreign key column in broker_positions
    rename_column :broker_positions, :ibkr_connection_id, :broker_connection_id

    # Update unique index on connections: account_id unique per broker_type
    remove_index :broker_connections, :account_id
    add_index :broker_connections, [ :broker_type, :account_id ], unique: true
  end
end

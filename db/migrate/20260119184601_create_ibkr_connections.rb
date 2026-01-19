class CreateIbkrConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :ibkr_connections do |t|
      t.string :account_id, null: false
      t.string :name, null: false
      t.string :flex_token, null: false
      t.string :flex_query_id, null: false
      t.datetime :last_synced_at
      t.text :last_sync_error

      t.timestamps
    end

    add_index :ibkr_connections, :account_id, unique: true
  end
end

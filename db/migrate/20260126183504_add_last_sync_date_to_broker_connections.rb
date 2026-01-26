class AddLastSyncDateToBrokerConnections < ActiveRecord::Migration[8.1]
  def change
    add_column :broker_connections, :last_sync_date, :date
  end
end

class RemoveLastSyncDateFromBrokerConnections < ActiveRecord::Migration[8.1]
  def change
    remove_column :broker_connections, :last_sync_date, :date
  end
end

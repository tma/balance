class AddExchangeToBrokerPositions < ActiveRecord::Migration[8.1]
  def change
    add_column :broker_positions, :exchange, :string
  end
end

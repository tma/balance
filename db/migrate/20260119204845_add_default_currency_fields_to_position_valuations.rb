class AddDefaultCurrencyFieldsToPositionValuations < ActiveRecord::Migration[8.1]
  def change
    add_column :position_valuations, :value_in_default_currency, :decimal
    add_column :position_valuations, :exchange_rate, :decimal
  end
end

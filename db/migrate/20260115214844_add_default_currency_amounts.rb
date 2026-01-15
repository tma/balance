class AddDefaultCurrencyAmounts < ActiveRecord::Migration[8.1]
  def change
    # Add default currency value to assets (converted value in default currency)
    add_column :assets, :value_in_default_currency, :decimal
    add_column :assets, :exchange_rate, :decimal

    # Add default currency value to asset_valuations
    add_column :asset_valuations, :value_in_default_currency, :decimal
    add_column :asset_valuations, :exchange_rate, :decimal

    # Add default currency amount to transactions
    add_column :transactions, :amount_in_default_currency, :decimal
    add_column :transactions, :exchange_rate, :decimal

    # Add default currency balance to accounts
    add_column :accounts, :balance_in_default_currency, :decimal
    add_column :accounts, :exchange_rate, :decimal
  end
end

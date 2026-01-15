class AddDefaultToCurrencies < ActiveRecord::Migration[8.1]
  def change
    add_column :currencies, :default, :boolean, default: false, null: false
  end
end

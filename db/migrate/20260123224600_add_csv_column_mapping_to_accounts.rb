class AddCsvColumnMappingToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :csv_column_mapping, :text
  end
end

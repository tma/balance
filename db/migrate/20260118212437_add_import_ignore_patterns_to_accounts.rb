class AddImportIgnorePatternsToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :import_ignore_patterns, :text
  end
end

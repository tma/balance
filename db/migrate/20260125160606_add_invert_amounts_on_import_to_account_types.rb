class AddInvertAmountsOnImportToAccountTypes < ActiveRecord::Migration[8.1]
  def change
    add_column :account_types, :invert_amounts_on_import, :boolean, default: false, null: false
  end
end

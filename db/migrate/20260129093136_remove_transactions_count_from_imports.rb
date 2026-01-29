class RemoveTransactionsCountFromImports < ActiveRecord::Migration[8.1]
  def change
    remove_column :imports, :transactions_count, :integer
  end
end

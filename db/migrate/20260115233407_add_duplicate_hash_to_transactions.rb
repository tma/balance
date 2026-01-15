class AddDuplicateHashToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :duplicate_hash, :string
    add_index :transactions, :duplicate_hash
  end
end

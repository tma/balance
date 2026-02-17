class AddEmbeddingToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :embedding, :binary
  end
end

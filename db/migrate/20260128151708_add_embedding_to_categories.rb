class AddEmbeddingToCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :categories, :embedding, :binary
  end
end

class AddProgressMetaToImports < ActiveRecord::Migration[8.1]
  def change
    add_column :imports, :extracted_count, :integer
    add_column :imports, :progress_message, :string
  end
end

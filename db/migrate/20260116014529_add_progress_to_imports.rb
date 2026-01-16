class AddProgressToImports < ActiveRecord::Migration[8.1]
  def change
    add_column :imports, :progress, :string
  end
end

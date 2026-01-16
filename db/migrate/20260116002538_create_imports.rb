class CreateImports < ActiveRecord::Migration[8.1]
  def change
    create_table :imports do |t|
      t.references :account, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.string :original_filename
      t.string :file_content_type
      t.binary :file_data
      t.text :extracted_data
      t.text :error_message
      t.integer :transactions_count, default: 0
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :imports, :status
  end
end

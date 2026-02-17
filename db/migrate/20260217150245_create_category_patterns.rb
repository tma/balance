class CreateCategoryPatterns < ActiveRecord::Migration[8.1]
  def change
    create_table :category_patterns do |t|
      t.references :category, null: false, foreign_key: true
      t.string :pattern, null: false
      t.string :source, null: false, default: "human" # "human" or "machine"
      t.integer :match_count, default: 0
      t.decimal :confidence # 0.0-1.0, machine only
      t.timestamps
    end

    add_index :category_patterns, [ :pattern, :source ], unique: true
    add_index :category_patterns, [ :category_id, :source ]
  end
end

class DropMatchPatternsFromCategories < ActiveRecord::Migration[8.1]
  def change
    remove_column :categories, :match_patterns, :text
  end
end

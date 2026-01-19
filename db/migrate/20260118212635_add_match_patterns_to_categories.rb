class AddMatchPatternsToCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :categories, :match_patterns, :text
  end
end

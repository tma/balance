class MigrateMatchPatternsToCategoryPatterns < ActiveRecord::Migration[8.1]
  def up
    Category.where.not(match_patterns: [ nil, "" ]).find_each do |category|
      category.match_patterns.lines.map(&:strip).reject(&:blank?).each do |pattern|
        CategoryPattern.find_or_create_by!(
          category: category,
          pattern: pattern,
          source: "human"
        )
      end
    end
  end

  def down
    # Reverse: aggregate human patterns back into text field
    Category.find_each do |category|
      patterns = CategoryPattern.where(category: category, source: "human").pluck(:pattern)
      category.update_column(:match_patterns, patterns.join("\n")) if patterns.any?
    end
    CategoryPattern.delete_all
  end
end

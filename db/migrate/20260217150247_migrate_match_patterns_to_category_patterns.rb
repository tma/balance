class MigrateMatchPatternsToCategoryPatterns < ActiveRecord::Migration[8.1]
  def up
    Category.where.not(match_patterns: [ nil, "" ]).find_each do |category|
      category.match_patterns.lines.map(&:strip).reject(&:blank?).each do |pattern|
        CategoryPattern.create!(
          category: category,
          pattern: pattern,
          source: "human",
          match_count: 0
        )
      rescue ActiveRecord::RecordNotUnique
        # Pattern already exists (idempotent)
        next
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

require "test_helper"

class MigrateMatchPatternsTest < ActiveSupport::TestCase
  # Tests for the data migration logic (MigrateMatchPatternsToCategoryPatterns)
  # These test the extraction logic used during the historical migration.
  # The match_patterns column has since been removed from categories.

  test "multiline patterns are split correctly" do
    patterns_text = "Amazon\nWhole Foods\nTrader Joe's"
    result = patterns_text.lines.map(&:strip).reject(&:blank?)

    assert_equal [ "Amazon", "Whole Foods", "Trader Joe's" ], result
  end

  test "empty match_patterns produces no patterns" do
    result = "".lines.map(&:strip).reject(&:blank?)
    assert_equal [], result
  end

  test "whitespace-only lines are rejected" do
    patterns_text = "  Amazon  \n\n  \n  Whole Foods  \n  "
    result = patterns_text.lines.map(&:strip).reject(&:blank?)

    assert_equal [ "Amazon", "Whole Foods" ], result
  end

  test "single pattern without newline works" do
    patterns_text = "Amazon"
    result = patterns_text.lines.map(&:strip).reject(&:blank?)

    assert_equal [ "Amazon" ], result
  end

  test "category patterns are created correctly" do
    category = Category.create!(
      name: "Migration Test",
      category_type: "expense"
    )

    # Simulate migration logic using pattern strings
    patterns = [ "Store A", "Store B", "Store C" ]
    patterns.each do |pattern|
      CategoryPattern.find_or_create_by!(
        category: category,
        pattern: pattern,
        source: "human"
      )
    end

    result = CategoryPattern.where(category: category, source: "human").pluck(:pattern)
    assert_includes result, "Store A"
    assert_includes result, "Store B"
    assert_includes result, "Store C"
    assert_equal 3, result.size
  end

  test "pattern creation is idempotent" do
    category = Category.create!(
      name: "Idempotent Test",
      category_type: "expense"
    )

    patterns = [ "StoreX", "StoreY" ]

    # Run twice
    2.times do
      patterns.each do |pattern|
        CategoryPattern.find_or_create_by!(
          category: category,
          pattern: pattern,
          source: "human"
        )
      end
    end

    count = CategoryPattern.where(category: category, source: "human").count
    assert_equal 2, count
  end
end

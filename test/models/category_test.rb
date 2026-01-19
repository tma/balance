require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  test "match_patterns_list returns empty array when blank" do
    category = Category.new(name: "Test", category_type: "expense")
    assert_equal [], category.match_patterns_list
  end

  test "match_patterns_list parses newline-separated patterns" do
    category = Category.new(
      name: "Test",
      category_type: "expense",
      match_patterns: "Amazon\nWhole Foods\nTrader Joe's"
    )
    assert_equal [ "Amazon", "Whole Foods", "Trader Joe's" ], category.match_patterns_list
  end

  test "match_patterns_list strips whitespace and rejects blank lines" do
    category = Category.new(
      name: "Test",
      category_type: "expense",
      match_patterns: "  Amazon  \n\n  Whole Foods  \n  "
    )
    assert_equal [ "Amazon", "Whole Foods" ], category.match_patterns_list
  end

  test "has_match_patterns? returns false when empty" do
    category = Category.new(name: "Test", category_type: "expense")
    assert_not category.has_match_patterns?
  end

  test "has_match_patterns? returns true when patterns exist" do
    category = Category.new(
      name: "Test",
      category_type: "expense",
      match_patterns: "Amazon"
    )
    assert category.has_match_patterns?
  end
end

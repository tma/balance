require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  test "match_patterns_list returns empty array for new record" do
    category = Category.new(name: "Test", category_type: "expense")
    assert_equal [], category.match_patterns_list
  end

  test "match_patterns_list returns human patterns from CategoryPattern table" do
    category = categories(:groceries)
    # Fixtures have human patterns: "Whole Foods", "Trader Joe"
    patterns = category.match_patterns_list
    assert_includes patterns, "Whole Foods"
    assert_includes patterns, "Trader Joe"
  end

  test "match_patterns_list excludes machine patterns" do
    category = categories(:groceries)
    patterns = category.match_patterns_list
    # Fixture has machine pattern "COSTCO WHSE" — should not be in match_patterns_list
    assert_not_includes patterns, "COSTCO WHSE"
  end

  test "has_match_patterns? returns false when empty" do
    category = Category.create!(name: "No Patterns", category_type: "expense")
    assert_not category.has_match_patterns?
  end

  test "has_match_patterns? returns true when patterns exist" do
    category = categories(:groceries)
    assert category.has_match_patterns?
  end

  test "matches_description? returns true for matching pattern" do
    category = categories(:groceries)
    assert category.matches_description?("Payment to Whole Foods Market")
    assert category.matches_description?("TRADER JOE #123")
  end

  test "matches_description? returns false for non-matching description" do
    category = categories(:groceries)
    assert_not category.matches_description?("Payment to Netflix")
  end

  test "matches_description? returns false when no patterns" do
    category = Category.create!(name: "Bare", category_type: "expense")
    assert_not category.matches_description?("Anything")
  end

  test "find_by_pattern returns matching category via CategoryPattern" do
    category = categories(:groceries)
    # Fixtures have "Whole Foods" as human pattern

    result = Category.find_by_pattern("WHOLE FOODS MARKET #123", "expense")
    assert_equal category, result
  end

  test "find_by_pattern returns nil when no match" do
    result = Category.find_by_pattern("Random description", "expense")
    assert_nil result
  end

  test "embedding_text includes name and type" do
    category = Category.new(name: "Groceries", category_type: "expense")
    assert_equal "Groceries (expense)", category.embedding_text
  end

  test "embedding_text includes patterns when present" do
    category = categories(:groceries)
    text = category.embedding_text
    assert_includes text, "groceries (expense)"
    assert_includes text, "Whole Foods"
    assert_includes text, "Trader Joe"
  end

  test "embedding_vector returns nil when embedding is blank" do
    category = Category.new(name: "Test", category_type: "expense")
    assert_nil category.embedding_vector
  end

  test "embedding_vector unpacks binary to floats" do
    category = Category.new(name: "Test", category_type: "expense")
    original_vector = [ 0.1, 0.2, 0.3, 0.4, 0.5 ]
    category.embedding = original_vector.pack("f*")

    result = category.embedding_vector
    assert_equal 5, result.size
    original_vector.each_with_index do |val, i|
      assert_in_delta val, result[i], 0.0001
    end
  end

  test "embedding_vector= packs floats to binary" do
    category = Category.new(name: "Test", category_type: "expense")
    category.embedding_vector = [ 0.1, 0.2, 0.3 ]

    assert_not_nil category.embedding
    unpacked = category.embedding.unpack("f*")
    assert_equal 3, unpacked.size
  end

  test "embedding_vector= handles nil" do
    category = Category.new(name: "Test", category_type: "expense")
    category.embedding_vector = nil
    assert_nil category.embedding
  end

  test "schedule_embedding_update is called when name changes" do
    category = categories(:groceries)

    assert_enqueued_with(job: CategoryEmbeddingJob, args: [ category.id ]) do
      category.update!(name: "New Name")
    end
  end

  test "schedule_embedding_update is not called for non-name changes" do
    category = categories(:groceries)

    assert_no_enqueued_jobs(only: CategoryEmbeddingJob) do
      category.touch
    end
  end
end

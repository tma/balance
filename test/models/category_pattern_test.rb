require "test_helper"

class CategoryPatternTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "valid pattern is saved" do
    pattern = CategoryPattern.new(
      category: categories(:groceries),
      pattern: "Safeway",
      source: "human"
    )
    assert pattern.valid?
  end

  test "pattern is required" do
    pattern = CategoryPattern.new(
      category: categories(:groceries),
      source: "human"
    )
    assert_not pattern.valid?
    assert_includes pattern.errors[:pattern], "can't be blank"
  end

  test "source must be human or machine" do
    assert_raises(ArgumentError, "'invalid' is not a valid source") do
      CategoryPattern.new(
        category: categories(:groceries),
        pattern: "Safeway",
        source: "invalid"
      )
    end
  end

  test "source defaults to human" do
    pattern = CategoryPattern.new(
      category: categories(:groceries),
      pattern: "Safeway"
    )
    assert_equal "human", pattern.source
    assert pattern.valid?
  end

  test "pattern must be unique within source" do
    existing = category_patterns(:groceries_whole_foods)
    duplicate = CategoryPattern.new(
      category: categories(:entertainment),
      pattern: existing.pattern,
      source: existing.source
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:pattern], "has already been taken"
  end

  test "same pattern can exist with different sources" do
    # "Whole Foods" already exists as human, should be able to add as machine
    pattern = CategoryPattern.new(
      category: categories(:groceries),
      pattern: "Whole Foods",
      source: "machine",
      confidence: 0.9
    )
    assert pattern.valid?
  end

  test "human scope returns only human patterns" do
    results = CategoryPattern.human
    assert results.all?(&:human?)
    assert_not results.any?(&:machine?)
  end

  test "machine scope returns only machine patterns" do
    results = CategoryPattern.machine
    assert results.all?(&:machine?)
    assert_not results.any?(&:human?)
  end

  test "by_match_count scope orders by match_count descending" do
    results = CategoryPattern.by_match_count.pluck(:match_count)
    assert_equal results.sort.reverse, results
  end

  test "human? returns true for human source" do
    pattern = category_patterns(:groceries_whole_foods)
    assert pattern.human?
    assert_not pattern.machine?
  end

  test "machine? returns true for machine source" do
    pattern = category_patterns(:groceries_machine_costco)
    assert pattern.machine?
    assert_not pattern.human?
  end

  test "increment_match_count! increments by one" do
    pattern = category_patterns(:groceries_whole_foods)
    original_count = pattern.match_count
    pattern.increment_match_count!
    assert_equal original_count + 1, pattern.reload.match_count
  end

  test "creating a pattern enqueues CategoryEmbeddingJob" do
    assert_enqueued_with(job: CategoryEmbeddingJob) do
      CategoryPattern.create!(
        category: categories(:entertainment),
        pattern: "AMC Theater",
        source: "human"
      )
    end
  end

  test "destroying a pattern enqueues CategoryEmbeddingJob" do
    pattern = category_patterns(:groceries_machine_costco)
    assert_enqueued_with(job: CategoryEmbeddingJob, args: [ pattern.category_id ]) do
      pattern.destroy!
    end
  end

  test "default match_count is zero" do
    pattern = CategoryPattern.create!(
      category: categories(:entertainment),
      pattern: "Cinema",
      source: "machine",
      confidence: 0.7
    )
    assert_equal 0, pattern.match_count
  end
end

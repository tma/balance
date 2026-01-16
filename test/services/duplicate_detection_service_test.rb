require "test_helper"

class DuplicateDetectionServiceTest < ActiveSupport::TestCase
  test "generates consistent hash for same inputs" do
    hash1 = DuplicateDetectionService.hash_for("2026-01-15", 100.50, "Coffee Shop")
    hash2 = DuplicateDetectionService.hash_for("2026-01-15", 100.50, "Coffee Shop")

    assert_equal hash1, hash2
  end

  test "generates different hash for different dates" do
    hash1 = DuplicateDetectionService.hash_for("2026-01-15", 100.50, "Coffee Shop")
    hash2 = DuplicateDetectionService.hash_for("2026-01-16", 100.50, "Coffee Shop")

    assert_not_equal hash1, hash2
  end

  test "generates different hash for different amounts" do
    hash1 = DuplicateDetectionService.hash_for("2026-01-15", 100.50, "Coffee Shop")
    hash2 = DuplicateDetectionService.hash_for("2026-01-15", 100.51, "Coffee Shop")

    assert_not_equal hash1, hash2
  end

  test "generates different hash for different descriptions" do
    hash1 = DuplicateDetectionService.hash_for("2026-01-15", 100.50, "Coffee Shop")
    hash2 = DuplicateDetectionService.hash_for("2026-01-15", 100.50, "Tea Shop")

    assert_not_equal hash1, hash2
  end

  test "normalizes description case and whitespace" do
    hash1 = DuplicateDetectionService.hash_for("2026-01-15", 100.50, "Coffee Shop")
    hash2 = DuplicateDetectionService.hash_for("2026-01-15", 100.50, "  COFFEE   SHOP  ")

    assert_equal hash1, hash2
  end

  test "accepts Date objects for date parameter" do
    hash1 = DuplicateDetectionService.hash_for(Date.new(2026, 1, 15), 100.50, "Coffee")
    hash2 = DuplicateDetectionService.hash_for("2026-01-15", 100.50, "Coffee")

    assert_equal hash1, hash2
  end

  test "normalizes amount precision" do
    hash1 = DuplicateDetectionService.hash_for("2026-01-15", 100.5, "Coffee")
    hash2 = DuplicateDetectionService.hash_for("2026-01-15", 100.50, "Coffee")
    hash3 = DuplicateDetectionService.hash_for("2026-01-15", "100.50", "Coffee")

    assert_equal hash1, hash2
    assert_equal hash2, hash3
  end

  test "find_existing_hashes returns empty set for empty input" do
    result = DuplicateDetectionService.find_existing_hashes([])

    assert_equal Set.new, result
  end

  test "find_existing_hashes finds existing transactions" do
    transaction = transactions(:paycheck)
    # Manually set the duplicate hash directly (bypassing validation to test lookup)
    Transaction.where(id: transaction.id).update_all(duplicate_hash: "test_hash_123")

    result = DuplicateDetectionService.find_existing_hashes([ "test_hash_123", "not_found" ])

    assert_includes result, "test_hash_123"
    assert_not_includes result, "not_found"
  end

  test "duplicate? returns true for existing transaction" do
    transaction = transactions(:paycheck)
    # Ensure the transaction has a duplicate_hash set
    transaction.save! # This triggers the before_save callback

    result = DuplicateDetectionService.duplicate?(
      transaction.date,
      transaction.amount,
      transaction.description
    )

    assert result
  end

  test "duplicate? returns false for new transaction" do
    result = DuplicateDetectionService.duplicate?(
      Date.new(2099, 12, 31),
      999999.99,
      "Unique transaction that doesn't exist"
    )

    assert_not result
  end

  test "mark_duplicates adds hash and duplicate flag to transactions" do
    transactions = [
      { date: Date.new(2026, 1, 15), amount: 50.0, description: "Test" },
      { date: Date.new(2026, 1, 16), amount: 75.0, description: "Another" }
    ]

    result = DuplicateDetectionService.mark_duplicates(transactions)

    assert_equal 2, result.size
    result.each do |txn|
      assert txn.key?(:duplicate_hash)
      assert txn.key?(:is_duplicate)
      assert_kind_of String, txn[:duplicate_hash]
    end
  end
end

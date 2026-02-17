require "test_helper"

class CategorizationMaintenanceJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @groceries = categories(:groceries)
    @entertainment = categories(:entertainment)
  end

  test "prunes stale machine patterns with zero matches after 30 days" do
    stale = CategoryPattern.create!(
      category: @entertainment,
      pattern: "STALE MERCHANT",
      source: "machine",
      match_count: 0,
      confidence: 0.5,
      created_at: 31.days.ago
    )

    CategorizationMaintenanceJob.perform_now

    assert_not CategoryPattern.exists?(stale.id), "Stale pattern should be deleted"
  end

  test "keeps recent machine patterns with zero matches" do
    recent = CategoryPattern.create!(
      category: @entertainment,
      pattern: "NEW MERCHANT",
      source: "machine",
      match_count: 0,
      confidence: 0.5,
      created_at: 5.days.ago
    )

    CategorizationMaintenanceJob.perform_now

    assert CategoryPattern.exists?(recent.id), "Recent pattern should not be deleted"
  end

  test "keeps stale machine patterns with nonzero match count" do
    active = CategoryPattern.create!(
      category: @entertainment,
      pattern: "ACTIVE MERCHANT",
      source: "machine",
      match_count: 5,
      confidence: 0.8,
      created_at: 60.days.ago
    )

    CategorizationMaintenanceJob.perform_now

    assert CategoryPattern.exists?(active.id), "Active pattern should not be deleted"
  end

  test "never prunes human patterns" do
    human = CategoryPattern.create!(
      category: @entertainment,
      pattern: "ALWAYS KEEP",
      source: "human",
      match_count: 0,
      created_at: 60.days.ago
    )

    CategorizationMaintenanceJob.perform_now

    assert CategoryPattern.exists?(human.id), "Human patterns should never be pruned"
  end

  test "detects recategorization drift and removes drifted patterns" do
    # Create a machine pattern pointing to groceries
    drifted = CategoryPattern.create!(
      category: @groceries,
      pattern: "drifted store",
      source: "machine",
      match_count: 5,
      confidence: 0.8
    )

    # Create transactions that match the pattern but belong to entertainment (user recategorized)
    5.times do
      Transaction.create!(
        account: accounts(:checking_account),
        category: @entertainment,
        amount: 25.0,
        transaction_type: "expense",
        date: Date.current,
        description: "Purchase at drifted store"
      )
    end

    CategorizationMaintenanceJob.perform_now

    assert_not CategoryPattern.exists?(drifted.id), "Drifted pattern should be removed"
  end

  # Note: resolving conflicting machine patterns (same pattern text, different categories)
  # is impossible to test because the unique index on [pattern, source] prevents duplicates.
  # The resolve_conflicting_patterns method in the job acts as defense-in-depth but the
  # DB constraint makes this scenario unreachable in practice.

  test "runs without error on empty database" do
    CategoryPattern.machine.delete_all

    assert_nothing_raised do
      CategorizationMaintenanceJob.perform_now
    end
  end
end

# frozen_string_literal: true

require "test_helper"

class AccountCoverageTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:checking_account)
    @category = categories(:groceries)
    # Freeze time so tests don't flag "gap to today"
    travel_to Date.new(2025, 6, 15)
  end

  teardown do
    travel_back
  end

  test "coverage_analysis returns nil for account with no imports" do
    @account.imports.destroy_all
    assert_nil @account.coverage_analysis
  end

  test "coverage_analysis returns nil for account with only pending imports" do
    @account.imports.destroy_all
    create_import(@account, status: "pending")

    assert_nil @account.coverage_analysis
  end

  test "coverage_analysis returns nil for account with done imports but no transactions" do
    @account.imports.destroy_all
    create_import(@account, status: "done")

    assert_nil @account.coverage_analysis
  end

  test "coverage_analysis returns complete for single recent import with transactions" do
    @account.imports.destroy_all
    import = create_import(@account, status: "done")
    # Use dates within threshold of "today" (June 15, 2025)
    create_transaction(@account, import, date: Date.new(2025, 5, 15))
    create_transaction(@account, import, date: Date.new(2025, 6, 14))

    result = @account.coverage_analysis

    assert_not_nil result
    assert_equal @account, result[:account]
    assert_equal Date.new(2025, 5, 15), result[:first_date]
    assert_equal Date.new(2025, 6, 14), result[:last_date]
    assert_equal 1, result[:periods].size
    assert_empty result[:gaps]
    assert result[:complete?]
  end

  test "coverage_analysis merges adjacent imports within threshold" do
    @account.imports.destroy_all

    # Import 1: May 1 - May 31
    import1 = create_import(@account, status: "done")
    create_transaction(@account, import1, date: Date.new(2025, 5, 1))
    create_transaction(@account, import1, date: Date.new(2025, 5, 31))

    # Import 2: Jun 1 - Jun 14 (only 1 day gap, within threshold)
    import2 = create_import(@account, status: "done")
    create_transaction(@account, import2, date: Date.new(2025, 6, 1))
    create_transaction(@account, import2, date: Date.new(2025, 6, 14))

    result = @account.coverage_analysis

    assert_equal 1, result[:periods].size
    assert_empty result[:gaps]
    assert result[:complete?]
  end

  test "coverage_analysis detects gap between imports" do
    @account.imports.destroy_all

    # Import 1: Jan 15 - Feb 14
    import1 = create_import(@account, status: "done")
    create_transaction(@account, import1, date: Date.new(2025, 1, 15))
    create_transaction(@account, import1, date: Date.new(2025, 2, 14))

    # Import 2: Apr 1 - Jun 14 (gap of ~45 days between periods, recent enough to not flag gap to today)
    import2 = create_import(@account, status: "done")
    create_transaction(@account, import2, date: Date.new(2025, 4, 1))
    create_transaction(@account, import2, date: Date.new(2025, 6, 14))

    result = @account.coverage_analysis

    assert_equal 2, result[:periods].size
    assert_equal 1, result[:gaps].size
    assert_not result[:complete?]

    gap = result[:gaps].first
    assert_equal Date.new(2025, 2, 15), gap[:start]
    assert_equal Date.new(2025, 3, 31), gap[:end]
    assert_equal 45, gap[:days]
  end

  test "coverage_analysis merges overlapping imports" do
    @account.imports.destroy_all

    # Import 1: Apr 15 - May 20
    import1 = create_import(@account, status: "done")
    create_transaction(@account, import1, date: Date.new(2025, 4, 15))
    create_transaction(@account, import1, date: Date.new(2025, 5, 20))

    # Import 2: May 10 - Jun 14 (overlaps with import 1)
    import2 = create_import(@account, status: "done")
    create_transaction(@account, import2, date: Date.new(2025, 5, 10))
    create_transaction(@account, import2, date: Date.new(2025, 6, 14))

    result = @account.coverage_analysis

    assert_equal 1, result[:periods].size
    assert_equal Date.new(2025, 4, 15), result[:first_date]
    assert_equal Date.new(2025, 6, 14), result[:last_date]
    assert_empty result[:gaps]
    assert result[:complete?]
  end

  test "coverage_analysis ignores imports that are not done" do
    @account.imports.destroy_all

    # Done import: May 15 - Jun 14
    done_import = create_import(@account, status: "done")
    create_transaction(@account, done_import, date: Date.new(2025, 5, 15))
    create_transaction(@account, done_import, date: Date.new(2025, 6, 14))

    # Completed but not done import: Jun 15 - Jun 30
    completed_import = create_import(@account, status: "completed")
    create_transaction(@account, completed_import, date: Date.new(2025, 6, 15))
    create_transaction(@account, completed_import, date: Date.new(2025, 6, 30))

    result = @account.coverage_analysis

    # Should only see the done import
    assert_equal 1, result[:periods].size
    assert_equal Date.new(2025, 5, 15), result[:first_date]
    assert_equal Date.new(2025, 6, 14), result[:last_date]
  end

  test "coverage_analysis handles multiple gaps" do
    @account.imports.destroy_all

    # Import 1: Jan 15 - Jan 31
    import1 = create_import(@account, status: "done")
    create_transaction(@account, import1, date: Date.new(2025, 1, 15))
    create_transaction(@account, import1, date: Date.new(2025, 1, 31))

    # Import 2: Mar 1 - Mar 31 (gap 1: Feb)
    import2 = create_import(@account, status: "done")
    create_transaction(@account, import2, date: Date.new(2025, 3, 1))
    create_transaction(@account, import2, date: Date.new(2025, 3, 31))

    # Import 3: May 15 - Jun 14 (gap 2: Apr + early May)
    import3 = create_import(@account, status: "done")
    create_transaction(@account, import3, date: Date.new(2025, 5, 15))
    create_transaction(@account, import3, date: Date.new(2025, 6, 14))

    result = @account.coverage_analysis

    assert_equal 3, result[:periods].size
    assert_equal 2, result[:gaps].size  # Two gaps between imports, none to today
    assert_not result[:complete?]
  end

  test "coverage_analysis does not flag gaps within threshold" do
    @account.imports.destroy_all

    # Import 1: May 1 - May 31
    import1 = create_import(@account, status: "done")
    create_transaction(@account, import1, date: Date.new(2025, 5, 1))
    create_transaction(@account, import1, date: Date.new(2025, 5, 31))

    # Import 2: Jun 8 - Jun 14 (gap of 7 days = exactly at threshold)
    import2 = create_import(@account, status: "done")
    create_transaction(@account, import2, date: Date.new(2025, 6, 8))
    create_transaction(@account, import2, date: Date.new(2025, 6, 14))

    result = @account.coverage_analysis

    # 7 day gap should be merged (threshold is 7 days)
    assert_equal 1, result[:periods].size
    assert_empty result[:gaps]
    assert result[:complete?]
  end

  test "coverage_analysis flags gaps just above threshold" do
    @account.imports.destroy_all

    # Import 1: Apr 1 - Apr 30
    import1 = create_import(@account, status: "done")
    create_transaction(@account, import1, date: Date.new(2025, 4, 1))
    create_transaction(@account, import1, date: Date.new(2025, 4, 30))

    # Import 2: May 9 - Jun 14 (gap of 8 days = above threshold)
    import2 = create_import(@account, status: "done")
    create_transaction(@account, import2, date: Date.new(2025, 5, 9))
    create_transaction(@account, import2, date: Date.new(2025, 6, 14))

    result = @account.coverage_analysis

    assert_equal 2, result[:periods].size
    assert_equal 1, result[:gaps].size
    assert_not result[:complete?]

    gap = result[:gaps].first
    assert_equal 8, gap[:days]
  end

  test "coverage_analysis flags gap from last import to today when stale" do
    @account.imports.destroy_all

    # Import with old data: Jan 15 - Jan 31 (today is June 15)
    import = create_import(@account, status: "done")
    create_transaction(@account, import, date: Date.new(2025, 1, 15))
    create_transaction(@account, import, date: Date.new(2025, 1, 31))

    result = @account.coverage_analysis

    assert_equal 1, result[:periods].size
    assert_equal 1, result[:gaps].size
    assert_not result[:complete?]

    gap = result[:gaps].first
    assert_equal Date.new(2025, 2, 1), gap[:start]
    assert_equal Date.new(2025, 6, 15), gap[:end]  # Today
    assert_equal 135, gap[:days]  # Feb 1 to Jun 15
  end

  test "coverage_analysis does not flag gap to today when within threshold" do
    @account.imports.destroy_all

    # Import ending 7 days ago (today is June 15, so June 8)
    import = create_import(@account, status: "done")
    create_transaction(@account, import, date: Date.new(2025, 5, 15))
    create_transaction(@account, import, date: Date.new(2025, 6, 8))

    result = @account.coverage_analysis

    assert_equal 1, result[:periods].size
    assert_empty result[:gaps]
    assert result[:complete?]
  end

  private

  def create_import(account, status:)
    Import.create!(
      account: account,
      status: status,
      original_filename: "test_#{SecureRandom.hex(4)}.csv",
      file_content_type: "text/csv",
      file_data: "test"
    )
  end

  def create_transaction(account, import, date:)
    Transaction.create!(
      account: account,
      import: import,
      category: @category,
      date: date,
      description: "Test transaction",
      amount: 100.00,
      transaction_type: "expense"
    )
  end
end

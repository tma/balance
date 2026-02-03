# frozen_string_literal: true

require "test_helper"

class AccountCoverageTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:checking_account)
    @category = categories(:groceries)
    # Enable coverage tracking with 7-day threshold (weekly)
    @account.update!(expected_transaction_frequency: 7)
    # Clear existing transactions
    @account.transactions.destroy_all
    # Freeze time so tests don't flag "gap to today"
    travel_to Date.new(2025, 6, 15)
  end

  teardown do
    travel_back
  end

  test "coverage_analysis returns nil for account with no expected_transaction_frequency (opt-out)" do
    @account.update!(expected_transaction_frequency: nil)
    create_transaction(@account, date: Date.new(2025, 5, 15))

    assert_nil @account.coverage_analysis
  end

  test "coverage_analysis returns nil for account with no transactions" do
    assert_nil @account.coverage_analysis
  end

  test "coverage_analysis returns complete for recent transactions within threshold" do
    # Transactions all within 7 days of each other, ending within threshold of "today" (June 15, 2025)
    create_transaction(@account, date: Date.new(2025, 6, 1))
    create_transaction(@account, date: Date.new(2025, 6, 7))   # 6 days later
    create_transaction(@account, date: Date.new(2025, 6, 14))  # 7 days later

    result = @account.reload.coverage_analysis

    assert_not_nil result
    assert_equal @account, result[:account]
    assert_equal Date.new(2025, 6, 1), result[:first_date]
    assert_equal Date.new(2025, 6, 14), result[:last_date]
    assert_equal 1, result[:periods].size
    assert_empty result[:gaps]
    assert result[:complete?]
    assert_equal 7, result[:threshold]
  end

  test "coverage_analysis merges adjacent transactions within threshold" do
    # Transactions with gaps <= 7 days should merge into one period
    create_transaction(@account, date: Date.new(2025, 6, 1))
    create_transaction(@account, date: Date.new(2025, 6, 8))   # 7 days gap (Jun 2-7 = 6 days between)
    create_transaction(@account, date: Date.new(2025, 6, 14))  # 6 days gap

    result = @account.reload.coverage_analysis

    assert_equal 1, result[:periods].size
    assert_empty result[:gaps]
    assert result[:complete?]
  end

  test "coverage_analysis detects gap between transaction clusters" do
    # Two clusters with a gap > 7 days between them
    # Cluster 1: Jan 10-15 (5 days span, within threshold)
    create_transaction(@account, date: Date.new(2025, 1, 10))
    create_transaction(@account, date: Date.new(2025, 1, 15))

    # Gap: Jan 16-31 (16 days)
    # Cluster 2: Feb 1-8 then continuing to today
    create_transaction(@account, date: Date.new(2025, 2, 1))
    create_transaction(@account, date: Date.new(2025, 2, 8))
    create_transaction(@account, date: Date.new(2025, 2, 15))
    create_transaction(@account, date: Date.new(2025, 2, 22))
    create_transaction(@account, date: Date.new(2025, 3, 1))
    create_transaction(@account, date: Date.new(2025, 3, 8))
    create_transaction(@account, date: Date.new(2025, 3, 15))
    create_transaction(@account, date: Date.new(2025, 3, 22))
    create_transaction(@account, date: Date.new(2025, 3, 29))
    create_transaction(@account, date: Date.new(2025, 4, 5))
    create_transaction(@account, date: Date.new(2025, 4, 12))
    create_transaction(@account, date: Date.new(2025, 4, 19))
    create_transaction(@account, date: Date.new(2025, 4, 26))
    create_transaction(@account, date: Date.new(2025, 5, 3))
    create_transaction(@account, date: Date.new(2025, 5, 10))
    create_transaction(@account, date: Date.new(2025, 5, 17))
    create_transaction(@account, date: Date.new(2025, 5, 24))
    create_transaction(@account, date: Date.new(2025, 5, 31))
    create_transaction(@account, date: Date.new(2025, 6, 7))
    create_transaction(@account, date: Date.new(2025, 6, 14))

    result = @account.reload.coverage_analysis

    assert_equal 2, result[:periods].size
    assert_equal 1, result[:gaps].size
    assert_not result[:complete?]

    gap = result[:gaps].first
    assert_equal Date.new(2025, 1, 16), gap[:start]
    assert_equal Date.new(2025, 1, 31), gap[:end]
    assert_equal 16, gap[:days]
  end

  test "coverage_analysis handles multiple gaps" do
    # Three clusters with two gaps (each > 7 days)
    # Cluster 1: Jan 1-7
    create_transaction(@account, date: Date.new(2025, 1, 1))
    create_transaction(@account, date: Date.new(2025, 1, 7))

    # Gap: Jan 8-19 (12 days)
    # Cluster 2: Jan 20-26
    create_transaction(@account, date: Date.new(2025, 1, 20))
    create_transaction(@account, date: Date.new(2025, 1, 26))

    # Gap: Jan 27 - Feb 9 (14 days)
    # Cluster 3: Feb 10 onwards with weekly transactions to today
    create_transaction(@account, date: Date.new(2025, 2, 10))
    create_transaction(@account, date: Date.new(2025, 2, 17))
    create_transaction(@account, date: Date.new(2025, 2, 24))
    create_transaction(@account, date: Date.new(2025, 3, 3))
    create_transaction(@account, date: Date.new(2025, 3, 10))
    create_transaction(@account, date: Date.new(2025, 3, 17))
    create_transaction(@account, date: Date.new(2025, 3, 24))
    create_transaction(@account, date: Date.new(2025, 3, 31))
    create_transaction(@account, date: Date.new(2025, 4, 7))
    create_transaction(@account, date: Date.new(2025, 4, 14))
    create_transaction(@account, date: Date.new(2025, 4, 21))
    create_transaction(@account, date: Date.new(2025, 4, 28))
    create_transaction(@account, date: Date.new(2025, 5, 5))
    create_transaction(@account, date: Date.new(2025, 5, 12))
    create_transaction(@account, date: Date.new(2025, 5, 19))
    create_transaction(@account, date: Date.new(2025, 5, 26))
    create_transaction(@account, date: Date.new(2025, 6, 2))
    create_transaction(@account, date: Date.new(2025, 6, 9))
    create_transaction(@account, date: Date.new(2025, 6, 14))

    result = @account.reload.coverage_analysis

    assert_equal 3, result[:periods].size
    assert_equal 2, result[:gaps].size
    assert_not result[:complete?]
  end

  test "coverage_analysis does not flag gaps within threshold" do
    # Gap of exactly 7 days should be merged
    create_transaction(@account, date: Date.new(2025, 5, 31))
    create_transaction(@account, date: Date.new(2025, 6, 8))  # 7 days gap
    create_transaction(@account, date: Date.new(2025, 6, 14))

    result = @account.reload.coverage_analysis

    assert_equal 1, result[:periods].size
    assert_empty result[:gaps]
    assert result[:complete?]
  end

  test "coverage_analysis flags gaps just above threshold" do
    # Gap of 8 days should be flagged (threshold is 7)
    # May 1 to May 10 = 9 days apart, gap between = 8 days (May 2-9)
    create_transaction(@account, date: Date.new(2025, 5, 1))
    create_transaction(@account, date: Date.new(2025, 5, 10))  # 8 days gap
    # Continue to today with weekly transactions
    create_transaction(@account, date: Date.new(2025, 5, 17))
    create_transaction(@account, date: Date.new(2025, 5, 24))
    create_transaction(@account, date: Date.new(2025, 5, 31))
    create_transaction(@account, date: Date.new(2025, 6, 7))
    create_transaction(@account, date: Date.new(2025, 6, 14))

    result = @account.reload.coverage_analysis

    assert_equal 2, result[:periods].size
    assert_equal 1, result[:gaps].size
    assert_not result[:complete?]

    gap = result[:gaps].first
    assert_equal 8, gap[:days]
  end

  test "coverage_analysis flags gap from last transaction to today when stale" do
    # Old transactions, today is June 15, threshold is 7
    # Last transaction Jan 15 → gap to today is 151 days
    create_transaction(@account, date: Date.new(2025, 1, 10))
    create_transaction(@account, date: Date.new(2025, 1, 15))

    result = @account.reload.coverage_analysis

    assert_equal 1, result[:periods].size
    assert_equal 1, result[:gaps].size
    assert_not result[:complete?]

    gap = result[:gaps].first
    assert_equal Date.new(2025, 1, 16), gap[:start]
    assert_equal Date.new(2025, 6, 15), gap[:end]  # Today
    assert_equal 151, gap[:days]
  end

  test "coverage_analysis does not flag gap to today when within threshold" do
    # Transaction within 7 days of today (June 15)
    # June 8 to June 15 = 7 days, gap = 6 days (within threshold)
    create_transaction(@account, date: Date.new(2025, 6, 1))
    create_transaction(@account, date: Date.new(2025, 6, 8))

    result = @account.reload.coverage_analysis

    assert_equal 1, result[:periods].size
    assert_empty result[:gaps]
    assert result[:complete?]
  end

  test "coverage_analysis respects different frequency thresholds" do
    # Transactions with 14-day gap (Jun 1 to Jun 14 = 13 days between)
    create_transaction(@account, date: Date.new(2025, 6, 1))
    create_transaction(@account, date: Date.new(2025, 6, 14))

    # With 7-day threshold, this should show a gap (13 > 7)
    @account.update!(expected_transaction_frequency: 7)
    result = @account.reload.coverage_analysis
    assert_equal 2, result[:periods].size
    assert_equal 1, result[:gaps].size
    assert_not result[:complete?]

    # With 30-day threshold, this should be merged (13 <= 30)
    @account.update!(expected_transaction_frequency: 30)
    result = @account.reload.coverage_analysis
    assert_equal 1, result[:periods].size
    assert_empty result[:gaps]
    assert result[:complete?]
  end

  test "coverage_analysis counts all transactions regardless of import" do
    # Mix of imported and manual transactions, all within threshold
    import = Import.create!(
      account: @account,
      status: "done",
      original_filename: "test.csv",
      file_content_type: "text/csv",
      file_data: "test"
    )

    # Imported transaction
    Transaction.create!(
      account: @account,
      import: import,
      category: @category,
      date: Date.new(2025, 6, 1),
      description: "Imported",
      amount: 100.00,
      transaction_type: "expense"
    )

    # Manual transactions (no import)
    create_transaction(@account, date: Date.new(2025, 6, 7))
    create_transaction(@account, date: Date.new(2025, 6, 14))

    result = @account.reload.coverage_analysis

    assert_equal 1, result[:periods].size
    assert_equal Date.new(2025, 6, 1), result[:first_date]
    assert_equal Date.new(2025, 6, 14), result[:last_date]
    assert_empty result[:gaps]
    assert result[:complete?]
  end

  private

  def create_transaction(account, date:)
    Transaction.create!(
      account: account,
      import: nil,
      category: @category,
      date: date,
      description: "Test transaction",
      amount: 100.00,
      transaction_type: "expense"
    )
  end
end

require "test_helper"

class CostOfLivingProjectionServiceTest < ActiveSupport::TestCase
  setup do
    ExpenseProfile.delete_all
    Transaction.delete_all
    @account = accounts(:checking_account)
    @as_of = Date.new(2026, 9, 3)
  end

  test "combines annual fixed commitment with annualized essential variable mean" do
    insurance = Category.create!(name: "Required insurance", category_type: "expense", essentiality: "essential")
    groceries = categories(:groceries)
    profile = ExpenseProfile.create!(
      category: insurance,
      merchant_pattern: "Home Policy",
      essentiality: "essential",
      cadence: "annual",
      confirmed_amount: 1200,
      source: "human",
      status: "confirmed"
    )
    create_expense(insurance, "HOME POLICY", "2026-02-01", 1200)
    6.times do |offset|
      create_expense(groceries, "LOCAL MARKET", Date.new(2026, 2, 1) + offset.months, 300)
    end

    result = CostOfLivingProjectionService.new(as_of: @as_of).call

    assert_equal 1200.to_d, result[:fixed_annual]
    assert_equal 3600.to_d, result[:variable_annual]
    assert_equal 4800.to_d, result[:annual]
    assert_includes result[:fixed_profiles], profile
  end

  test "sparse healthcare remains in annual variable cost" do
    healthcare = Category.create!(name: "Sparse healthcare", category_type: "expense", essentiality: "essential")
    create_expense(healthcare, "DOCTOR", "2026-02-01", 600)
    5.times do |offset|
      create_expense(categories(:entertainment), "OTHER", Date.new(2026, 3, 1) + offset.months, 10)
    end

    result = CostOfLivingProjectionService.new(as_of: @as_of).call

    assert_equal 1200.to_d, result[:variable_annual]
  end

  test "refunds reduce essential variable spending" do
    groceries = categories(:groceries)
    create_expense(groceries, "LOCAL MARKET", "2026-07-01", 300)
    create_transaction(groceries, "LOCAL MARKET REFUND", "2026-07-02", 50, "income")

    result = CostOfLivingProjectionService.new(as_of: @as_of).call

    assert_equal 3000.to_d, result[:variable_annual]
  end

  test "fixed transactions are not double counted as variable" do
    groceries = categories(:groceries)
    ExpenseProfile.create!(
      category: groceries,
      merchant_pattern: "Meal Plan",
      essentiality: "essential",
      cadence: "monthly",
      confirmed_amount: 100,
      source: "human",
      status: "confirmed"
    )
    create_expense(groceries, "MEAL PLAN", "2026-07-01", 100)

    result = CostOfLivingProjectionService.new(as_of: @as_of).call

    assert_equal 1200.to_d, result[:fixed_annual]
    assert_equal 0.to_d, result[:variable_annual]
  end

  test "overlapping fixed commitments use only the longest pattern" do
    category = Category.create!(name: "Overlapping fixed", category_type: "expense", essentiality: "essential")
    short = ExpenseProfile.create!(
      category: category,
      merchant_pattern: "Amazon",
      essentiality: "essential",
      cadence: "monthly",
      confirmed_amount: 40,
      source: "human",
      status: "confirmed"
    )
    long = ExpenseProfile.create!(
      category: category,
      merchant_pattern: "Amazon Prime",
      essentiality: "essential",
      cadence: "monthly",
      confirmed_amount: 15,
      source: "human",
      status: "confirmed"
    )
    create_expense(category, "AMAZON PRIME", "2026-07-01", 15)

    result = CostOfLivingProjectionService.new(as_of: @as_of).call

    assert_equal [ long ], result[:fixed_profiles]
    assert_not_includes result[:fixed_profiles], short
    assert_equal 180.to_d, result[:fixed_annual]
  end

  test "mixed spending is disclosed without creating actionable review state" do
    mixed = Category.create!(name: "Mixed household", category_type: "expense", essentiality: "mixed")
    create_expense(mixed, "HOUSEHOLD STORE", "2026-07-01", 100)

    result = CostOfLivingProjectionService.new(as_of: @as_of).call

    assert_equal 1200.to_d, result[:unreviewed_annual]
    assert_equal 0, result[:completeness]
    assert result[:complete]
    assert_equal [ { category: mixed, annual: 1200.to_d } ], result[:unreviewed_categories]
    assert_equal 1200.to_d, result[:mixed_remainder_annual]
    assert_equal [ Transaction.find_by!(description: "HOUSEHOLD STORE").id ], result[:mixed_remainder_transaction_ids]
    assert_empty result[:unclassified_categories]
  end

  test "income does not reduce unreviewed expense impact" do
    unclassified = Category.create!(name: "Unclassified expense", category_type: "expense")
    create_expense(unclassified, "UNKNOWN COST", "2026-07-01", 100)
    create_transaction(categories(:salary), "PAYCHECK", "2026-07-01", 5000, "income")

    result = CostOfLivingProjectionService.new(as_of: @as_of).call

    assert_equal 1200.to_d, result[:unreviewed_annual]
    assert_not result[:complete]
    assert_equal [ "Unclassified expense" ], result[:unclassified_categories].map { |entry| entry[:category].name }
  end

  test "all covered months form the annualization denominator" do
    groceries = categories(:groceries)
    12.times do |offset|
      date = Date.new(2025, 9, 1) + offset.months
      create_transaction(categories(:salary), "PAYCHECK", date, 5000, "income")
      create_expense(groceries, "LOCAL MARKET", date, 100) if offset < 3
    end

    result = CostOfLivingProjectionService.new(as_of: @as_of).call

    assert_equal 300.to_d, result[:variable_annual]
    assert_equal 12, result[:included_months].size
  end

  test "uses a manual data-complete-through month for the amount window" do
    groceries = categories(:groceries)
    create_expense(groceries, "IN WINDOW", "2026-05-15", 100)
    create_expense(groceries, "AFTER CUTOFF", "2026-07-15", 900)
    period = CostOfLivingPeriodService.new(
      as_of: @as_of,
      data_complete_through: Date.new(2026, 6, 1)
    ).call

    result = CostOfLivingProjectionService.new(as_of: @as_of, period: period).call

    assert_equal Date.new(2026, 6, 1), result[:period][:data_complete_through]
    assert_equal 1200.to_d, result[:variable_annual]
  end

  test "open grouped suggestions keep an otherwise classified report incomplete" do
    groceries = categories(:groceries)
    create_expense(groceries, "LOCAL MARKET", "2026-07-01", 100)
    ExpenseProfile.create!(
      category: groceries,
      merchant_pattern: "Local Market",
      essentiality: "essential",
      source: "machine",
      status: "suggested",
      recurrence_confidence: "high",
      detected_cadence: "monthly",
      median_amount: 100,
      occurrence_count: 3
    )

    result = CostOfLivingProjectionService.new(as_of: @as_of).call

    assert_equal 100, result[:completeness]
    assert_equal 1, result[:open_suggestion_count]
    assert_not result[:complete]
  end

  test "suggestions in excluded categories do not require review" do
    excluded = Category.create!(name: "Excluded suggestion", category_type: "expense", essentiality: "excluded")
    create_expense(excluded, "SAVINGS TRANSFER", "2026-07-01", 1000)
    ExpenseProfile.create!(
      category: excluded,
      merchant_pattern: "Savings Transfer",
      essentiality: "excluded",
      source: "machine",
      status: "suggested",
      recurrence_confidence: "high",
      detected_cadence: "monthly",
      median_amount: 1000,
      occurrence_count: 3
    )

    result = CostOfLivingProjectionService.new(as_of: @as_of).call

    assert result[:complete]
    assert_empty result[:review_queue]
    assert_equal 0, result[:unreviewed_annual]
  end

  private

  def create_expense(category, description, date, amount)
    create_transaction(category, description, date, amount, "expense")
  end

  def create_transaction(category, description, date, amount, type)
    Transaction.create!(
      account: @account,
      category: category,
      amount: amount,
      transaction_type: type,
      date: Date.parse(date.to_s),
      description: description
    )
  end
end

require "test_helper"

class BudgetTest < ActiveSupport::TestCase
  setup do
    @monthly_budget = budgets(:groceries_budget)
    @yearly_budget = budgets(:vacation_budget)
  end

  test "valid budget" do
    assert @monthly_budget.valid?
    assert @yearly_budget.valid?
  end

  test "requires amount greater than 0" do
    @monthly_budget.amount = 0
    assert_not @monthly_budget.valid?

    @monthly_budget.amount = -10
    assert_not @monthly_budget.valid?
  end

  test "requires valid period" do
    @monthly_budget.period = "weekly"
    assert_not @monthly_budget.valid?

    @monthly_budget.period = ""
    assert_not @monthly_budget.valid?
  end

  test "requires unique category" do
    duplicate = Budget.new(
      category: @monthly_budget.category,
      amount: 300,
      period: "monthly"
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:category_id], "already has a budget"
  end

  test "monthly? returns true for monthly budgets" do
    assert @monthly_budget.monthly?
    assert_not @monthly_budget.yearly?
  end

  test "yearly? returns true for yearly budgets" do
    assert @yearly_budget.yearly?
    assert_not @yearly_budget.monthly?
  end

  test "period_label returns correct label" do
    assert_equal "per month", @monthly_budget.period_label
    assert_equal "per year", @yearly_budget.period_label
  end

  test "active_for? returns true when no start_date" do
    @monthly_budget.start_date = nil
    assert @monthly_budget.active_for?(Date.new(2020, 1, 1))
    assert @monthly_budget.active_for?(Date.new(2030, 12, 31))
  end

  test "active_for? respects start_date" do
    @yearly_budget.start_date = Date.new(2026, 6, 15)

    assert_not @yearly_budget.active_for?(Date.new(2026, 5, 1))
    assert @yearly_budget.active_for?(Date.new(2026, 6, 1))  # Beginning of month
    assert @yearly_budget.active_for?(Date.new(2026, 7, 1))
  end

  test "spent calculates monthly expenses" do
    # Create a transaction in the budget's category using a far future date to avoid interference
    account = accounts(:checking_account)
    Transaction.create!(
      account: account,
      category: @monthly_budget.category,
      amount: 50.00,
      transaction_type: "expense",
      date: Date.new(2099, 3, 15)
    )

    assert_equal 50.00, @monthly_budget.spent(2099, 3)
    assert_equal 0, @monthly_budget.spent(2099, 4)
  end

  test "spent calculates yearly expenses" do
    account = accounts(:checking_account)
    Transaction.create!(
      account: account,
      category: @yearly_budget.category,
      amount: 100.00,
      transaction_type: "expense",
      date: Date.new(2098, 1, 15)
    )
    Transaction.create!(
      account: account,
      category: @yearly_budget.category,
      amount: 200.00,
      transaction_type: "expense",
      date: Date.new(2098, 6, 15)
    )

    assert_equal 300.00, @yearly_budget.spent(2098)
    assert_equal 0, @yearly_budget.spent(2097)
  end

  test "remaining calculates correctly" do
    # With no transactions in the test date range, remaining equals amount
    assert_equal @monthly_budget.amount, @monthly_budget.remaining(2099, 1)
  end

  test "percentage_used calculates correctly" do
    account = accounts(:checking_account)
    Transaction.create!(
      account: account,
      category: @monthly_budget.category,
      amount: 250.00,
      transaction_type: "expense",
      date: Date.new(2099, 1, 15)
    )

    # 250 of 500 = 50%
    assert_equal 50.0, @monthly_budget.percentage_used(2099, 1)
  end

  test "percentage_used returns 0 when amount is zero" do
    @monthly_budget.amount = 0
    # Need to bypass validation for this test
    @monthly_budget.save(validate: false)
    assert_equal 0, @monthly_budget.percentage_used(2026, 1)
  end
end

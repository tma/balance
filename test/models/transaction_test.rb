require "test_helper"

class TransactionTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:checking_account)
    @expense_category = categories(:groceries)
    @income_category = categories(:salary)
  end

  test "signed_amount_sql returns positive for matching type" do
    Transaction.create!(
      account: @account,
      category: @expense_category,
      amount: 100.00,
      transaction_type: "expense",
      date: Date.new(2097, 1, 15)
    )

    total = Transaction.where(date: Date.new(2097, 1, 1)..Date.new(2097, 1, 31))
                       .sum(Transaction.signed_amount_sql("expense"))
    assert_equal 100.00, total
  end

  test "signed_amount_sql returns negative for non-matching type (refund)" do
    # Refund: income transaction on expense category
    Transaction.create!(
      account: @account,
      category: @expense_category,
      amount: 50.00,
      transaction_type: "income",
      date: Date.new(2097, 2, 15)
    )

    total = Transaction.where(date: Date.new(2097, 2, 1)..Date.new(2097, 2, 28))
                       .sum(Transaction.signed_amount_sql("expense"))
    assert_equal(-50.00, total)
  end

  test "signed_amount_sql nets expenses and refunds" do
    # Normal expense
    Transaction.create!(
      account: @account,
      category: @expense_category,
      amount: 200.00,
      transaction_type: "expense",
      date: Date.new(2097, 3, 10)
    )
    # Refund on same category
    Transaction.create!(
      account: @account,
      category: @expense_category,
      amount: 50.00,
      transaction_type: "income",
      date: Date.new(2097, 3, 20)
    )

    total = Transaction.where(date: Date.new(2097, 3, 1)..Date.new(2097, 3, 31))
                       .sum(Transaction.signed_amount_sql("expense"))
    assert_equal 150.00, total
  end

  test "signed_amount_by_category_type_sql groups by category type correctly" do
    # Expense on expense category (positive for expense)
    Transaction.create!(
      account: @account,
      category: @expense_category,
      amount: 300.00,
      transaction_type: "expense",
      date: Date.new(2097, 4, 10)
    )
    # Refund (income) on expense category (negative for expense)
    Transaction.create!(
      account: @account,
      category: @expense_category,
      amount: 100.00,
      transaction_type: "income",
      date: Date.new(2097, 4, 15)
    )
    # Income on income category (positive for income)
    Transaction.create!(
      account: @account,
      category: @income_category,
      amount: 1000.00,
      transaction_type: "income",
      date: Date.new(2097, 4, 10)
    )

    totals = Transaction.where(date: Date.new(2097, 4, 1)..Date.new(2097, 4, 30))
                        .joins(:category)
                        .group("categories.category_type")
                        .sum(Transaction.signed_amount_by_category_type_sql)

    assert_equal 200.00, totals["expense"]  # 300 - 100
    assert_equal 1000.00, totals["income"]
  end

  test "refund on expense category does not appear in income totals" do
    # Refund (income transaction on expense category)
    Transaction.create!(
      account: @account,
      category: @expense_category,
      amount: 75.00,
      transaction_type: "income",
      date: Date.new(2097, 5, 15)
    )

    totals = Transaction.where(date: Date.new(2097, 5, 1)..Date.new(2097, 5, 31))
                        .joins(:category)
                        .group("categories.category_type")
                        .sum(Transaction.signed_amount_by_category_type_sql)

    # Refund should appear under "expense" (as -75), not under "income"
    assert_equal(-75.00, totals["expense"])
    assert_nil totals["income"]
  end
end

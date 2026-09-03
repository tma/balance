require "test_helper"

class TransactionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @transaction = transactions(:paycheck)
  end

  test "should get index" do
    get transactions_url
    assert_response :success
  end

  test "should get index with month filter" do
    get transactions_url(month: Date.current.strftime("%Y-%m"))
    assert_response :success
  end

  test "should get index with date range" do
    get transactions_url(start_date: 1.month.ago.to_date, end_date: Date.current)
    assert_response :success
  end

  test "mixed remainder filter shows exact unmatched transactions" do
    ExpenseProfile.delete_all
    mixed = Category.create!(name: "Mixed drill-down", category_type: "expense", essentiality: "mixed")
    remainder = Transaction.create!(
      account: accounts(:checking_account),
      category: mixed,
      amount: 75,
      transaction_type: "expense",
      date: 1.month.ago.to_date,
      description: "UNMATCHED MIXED COST"
    )

    get transactions_url(cost_of_living: "mixed_remainder")

    assert_response :success
    assert_select "h2", "Mixed Remainder Transactions"
    assert_select "tr", text: /#{remainder.description}/
    assert_select "a[href=?]", cash_flow_path(view: "cost_of_living"), text: "Back to Cost of Living"
  end

  test "should get new" do
    get new_transaction_url
    assert_response :success
  end

  test "should create transaction" do
    assert_difference("Transaction.count") do
      post transactions_url, params: { transaction: { account_id: @transaction.account_id, amount: 100.00, category_id: @transaction.category_id, date: Date.current, description: "Test transaction", transaction_type: "income" } }
    end

    assert_redirected_to transactions_url
  end

  test "should get edit" do
    get edit_transaction_url(@transaction)
    assert_response :success
  end

  test "should update transaction" do
    patch transaction_url(@transaction), params: { transaction: { account_id: @transaction.account_id, amount: @transaction.amount, category_id: @transaction.category_id, date: @transaction.date, description: @transaction.description, transaction_type: @transaction.transaction_type } }
    assert_redirected_to transactions_url
  end

  test "should destroy transaction" do
    assert_difference("Transaction.count", -1) do
      delete transaction_url(@transaction)
    end

    assert_redirected_to transactions_url
  end
end

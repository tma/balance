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

  test "should get new" do
    get new_transaction_url
    assert_response :success
  end

  test "should create transaction" do
    assert_difference("Transaction.count") do
      post transactions_url, params: { transaction: { account_id: @transaction.account_id, amount: 100.00, category_id: @transaction.category_id, date: Date.current, description: "Test transaction", transaction_type: "income" } }
    end

    assert_redirected_to transaction_url(Transaction.last)
  end

  test "should show transaction" do
    get transaction_url(@transaction)
    assert_response :success
  end

  test "should get edit" do
    get edit_transaction_url(@transaction)
    assert_response :success
  end

  test "should update transaction" do
    patch transaction_url(@transaction), params: { transaction: { account_id: @transaction.account_id, amount: @transaction.amount, category_id: @transaction.category_id, date: @transaction.date, description: @transaction.description, transaction_type: @transaction.transaction_type } }
    assert_redirected_to transaction_url(@transaction)
  end

  test "should destroy transaction" do
    assert_difference("Transaction.count", -1) do
      delete transaction_url(@transaction)
    end

    assert_redirected_to transactions_url
  end
end

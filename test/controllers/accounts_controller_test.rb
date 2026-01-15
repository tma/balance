require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:checking_account)
  end

  test "should get index" do
    get accounts_url
    assert_response :success
  end

  test "should get new" do
    get new_account_url
    assert_response :success
  end

  test "should create account" do
    assert_difference("Account.count") do
      post accounts_url, params: { account: { account_type_id: @account.account_type_id, balance: 500.00, currency: @account.currency, name: "New Account" } }
    end

    assert_redirected_to account_url(Account.last)
  end

  test "should show account" do
    get account_url(@account)
    assert_response :success
  end

  test "should get edit" do
    get edit_account_url(@account)
    assert_response :success
  end

  test "should update account" do
    patch account_url(@account), params: { account: { account_type_id: @account.account_type_id, balance: @account.balance, currency: @account.currency, name: @account.name } }
    assert_redirected_to account_url(@account)
  end

  test "should destroy account" do
    # Create a new account without transactions to destroy
    account = Account.create!(name: "Test Delete", account_type: account_types(:checking), balance: 0, currency: "USD")
    assert_difference("Account.count", -1) do
      delete account_url(account)
    end

    assert_redirected_to accounts_url
  end
end

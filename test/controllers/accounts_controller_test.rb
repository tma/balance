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

    assert_redirected_to accounts_url
  end

  test "should get edit" do
    get edit_account_url(@account)
    assert_response :success
  end

  test "should update account" do
    patch account_url(@account), params: { account: { account_type_id: @account.account_type_id, balance: @account.balance, currency: @account.currency, name: @account.name } }
    assert_redirected_to accounts_url
  end

  test "should destroy account" do
    # Create a new account without transactions to destroy
    account = Account.create!(name: "Test Delete", account_type: account_types(:checking), balance: 0, currency: "USD")
    assert_difference("Account.count", -1) do
      delete account_url(account)
    end

    assert_redirected_to accounts_url
  end

  test "should archive account" do
    assert_not @account.archived?
    patch archive_account_url(@account)
    assert_redirected_to accounts_url
    assert @account.reload.archived?
  end

  test "should unarchive account" do
    @account.update!(archived: true)
    patch unarchive_account_url(@account)
    assert_redirected_to accounts_url
    assert_not @account.reload.archived?
  end

  test "should not archive account with pending imports" do
    Import.create!(
      account: @account,
      status: "pending",
      original_filename: "test.csv",
      file_content_type: "text/csv",
      file_data: "test data"
    )

    assert @account.has_pending_imports?
    patch archive_account_url(@account)
    assert_redirected_to accounts_url
    assert_not @account.reload.archived?
    assert_match(/Cannot archive/, flash[:alert])
  end
end

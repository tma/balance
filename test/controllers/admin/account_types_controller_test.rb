require "test_helper"

class Admin::AccountTypesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account_type = account_types(:checking)
  end

  test "should get index" do
    get admin_account_types_url
    assert_response :success
  end

  test "should get new" do
    get new_admin_account_type_url
    assert_response :success
  end

  test "should create account_type" do
    assert_difference("AccountType.count") do
      post admin_account_types_url, params: { account_type: { name: "investment" } }
    end

    assert_redirected_to admin_account_type_url(AccountType.last)
  end

  test "should show account_type" do
    get admin_account_type_url(@account_type)
    assert_response :success
  end

  test "should get edit" do
    get edit_admin_account_type_url(@account_type)
    assert_response :success
  end

  test "should update account_type" do
    patch admin_account_type_url(@account_type), params: { account_type: { name: @account_type.name } }
    assert_redirected_to admin_account_type_url(@account_type)
  end

  test "should destroy account_type" do
    # Create a new account type to destroy (not used by accounts)
    account_type = AccountType.create!(name: "test_type_to_delete")
    assert_difference("AccountType.count", -1) do
      delete admin_account_type_url(account_type)
    end

    assert_redirected_to admin_account_types_url
  end
end

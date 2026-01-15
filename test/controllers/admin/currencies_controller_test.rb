require "test_helper"

class Admin::CurrenciesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @currency = currencies(:usd)
  end

  test "should get index" do
    get admin_currencies_url
    assert_response :success
  end

  test "should get new" do
    get new_admin_currency_url
    assert_response :success
  end

  test "should create currency" do
    assert_difference("Currency.count") do
      post admin_currencies_url, params: { currency: { code: "GBP" } }
    end

    assert_redirected_to admin_currency_url(Currency.last)
  end

  test "should show currency" do
    get admin_currency_url(@currency)
    assert_response :success
  end

  test "should get edit" do
    get edit_admin_currency_url(@currency)
    assert_response :success
  end

  test "should update currency" do
    patch admin_currency_url(@currency), params: { currency: { code: "USD" } }
    assert_redirected_to admin_currency_url(@currency)
  end

  test "should destroy currency" do
    # Create a new currency to destroy (not used by accounts)
    currency = Currency.create!(code: "JPY")
    assert_difference("Currency.count", -1) do
      delete admin_currency_url(currency)
    end

    assert_redirected_to admin_currencies_url
  end
end

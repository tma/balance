require "test_helper"

class CurrencyTest < ActiveSupport::TestCase
  test "validates presence of code" do
    currency = Currency.new(code: nil)
    assert_not currency.valid?
    assert_includes currency.errors[:code], "can't be blank"
  end

  test "validates uniqueness of code" do
    # Use a code that doesn't exist in fixtures
    Currency.create!(code: "GBP")
    duplicate = Currency.new(code: "GBP")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:code], "has already been taken"
  end

  test "validates code format" do
    invalid_codes = %w[us usd US1 USDD]
    invalid_codes.each do |code|
      currency = Currency.new(code: code)
      assert_not currency.valid?, "#{code} should be invalid"
    end
  end

  test "valid code passes validation" do
    currency = Currency.new(code: "GBP")
    assert currency.valid?
  end

  test "only one currency can be default" do
    # Use codes not in fixtures
    gbp = Currency.create!(code: "GBP", default: true)
    chf = Currency.create!(code: "CHF", default: true)

    gbp.reload
    assert_not gbp.default?, "GBP should no longer be default"
    assert chf.default?, "CHF should now be default"
  end

  test "Currency.default returns the default currency" do
    # Use codes not in fixtures
    Currency.create!(code: "GBP", default: false)
    chf = Currency.create!(code: "CHF", default: true)

    assert_equal chf, Currency.default
  end

  test "Currency.default falls back to first currency if no default set" do
    # Clear any defaults from fixtures
    Currency.update_all(default: false)

    assert_equal Currency.first, Currency.default
  end
end

require "test_helper"

class CurrencyTest < ActiveSupport::TestCase
  test "validates presence of code" do
    currency = Currency.new(code: nil)
    assert_not currency.valid?
    assert_includes currency.errors[:code], "can't be blank"
  end

  test "validates uniqueness of code" do
    Currency.create!(code: "USD")
    duplicate = Currency.new(code: "USD")
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
    usd = Currency.create!(code: "USD", default: true)
    eur = Currency.create!(code: "EUR", default: true)

    usd.reload
    assert_not usd.default?, "USD should no longer be default"
    assert eur.default?, "EUR should now be default"
  end

  test "Currency.default returns the default currency" do
    Currency.create!(code: "USD", default: false)
    eur = Currency.create!(code: "EUR", default: true)

    assert_equal eur, Currency.default
  end

  test "Currency.default falls back to first currency if no default set" do
    Currency.create!(code: "USD", default: false)
    Currency.create!(code: "EUR", default: false)

    assert_equal Currency.first, Currency.default
  end
end

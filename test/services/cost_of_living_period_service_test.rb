require "test_helper"

class CostOfLivingPeriodServiceTest < ActiveSupport::TestCase
  setup do
    Transaction.delete_all
    @as_of = Date.new(2026, 9, 3)
  end

  test "defaults to the previous month without tracked account coverage" do
    result = CostOfLivingPeriodService.new(as_of: @as_of).call

    assert_equal Date.new(2026, 8, 1), result[:data_complete_through]
    assert_equal Date.new(2025, 9, 1), result[:window_start]
    assert_equal Date.new(2026, 8, 31), result[:window_end]
    assert_equal "automatic", result[:data_complete_through_source]
  end

  test "uses the oldest fully supported month across tracked accounts" do
    weekly = accounts(:checking_account)
    weekly.update!(expected_transaction_frequency: 7)
    monthly = accounts(:credit_card_account)
    monthly.update!(expected_transaction_frequency: 30)
    create_transaction(weekly, "2026-07-20")
    create_transaction(monthly, "2026-08-01")

    result = CostOfLivingPeriodService.new(as_of: @as_of).call

    assert_equal Date.new(2026, 6, 1), result[:automatic_data_complete_through]
    assert_equal [ weekly ], result[:limiting_accounts]
  end

  test "manual cutoff overrides automatic coverage" do
    result = CostOfLivingPeriodService.new(
      as_of: @as_of,
      data_complete_through: Date.new(2026, 5, 1)
    ).call

    assert_equal Date.new(2026, 5, 1), result[:data_complete_through]
    assert_equal "manual", result[:data_complete_through_source]
  end

  private

  def create_transaction(account, date)
    Transaction.create!(
      account: account,
      category: categories(:groceries),
      amount: 10,
      transaction_type: "expense",
      date: Date.parse(date),
      description: "COVERAGE TEST"
    )
  end
end

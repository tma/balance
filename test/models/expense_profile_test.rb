require "test_helper"

class ExpenseProfileTest < ActiveSupport::TestCase
  test "matches merchant pattern with word boundaries" do
    profile = expense_profiles(:whole_foods)

    assert profile.matches_description?("CARD WHOLE FOODS 123")
    assert_not profile.matches_description?("WHOLE FOODSTORE")
  end

  test "annualizes confirmed cadence" do
    profile = expense_profiles(:whole_foods)

    assert_equal 1800.to_d, profile.annualized_amount
  end

  test "confirmed recurring profile requires amount" do
    profile = ExpenseProfile.new(
      category: categories(:groceries),
      merchant_pattern: "Insurance",
      essentiality: "essential",
      cadence: "annual",
      source: "human",
      status: "confirmed"
    )

    assert_not profile.valid?
    assert_includes profile.errors[:confirmed_amount], "is required for a confirmed recurring profile"
  end

  test "income categories cannot own profiles" do
    profile = ExpenseProfile.new(
      category: categories(:salary),
      merchant_pattern: "Payroll",
      source: "machine",
      status: "suggested"
    )

    assert_not profile.valid?
    assert_includes profile.errors[:category], "must be an expense category"
  end
end

require "test_helper"

class BudgetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @budget = budgets(:groceries_budget)
    @yearly_budget = budgets(:vacation_budget)
  end

  test "should get index" do
    get budgets_url
    assert_response :success
  end

  test "should get index with month and year params" do
    get budgets_url, params: { year: 2026, month: 6 }
    assert_response :success
  end

  test "should get new" do
    get new_budget_url
    assert_response :success
  end

  test "should create monthly budget" do
    # Create a new category to avoid uniqueness constraint
    category = Category.create!(name: "utilities", category_type: "expense")
    assert_difference("Budget.count") do
      post budgets_url, params: { budget: { amount: 200.00, category_id: category.id, period: "monthly" } }
    end

    assert_redirected_to budget_url(Budget.last)
    assert_equal "monthly", Budget.last.period
  end

  test "should create yearly budget" do
    category = Category.create!(name: "insurance", category_type: "expense")
    assert_difference("Budget.count") do
      post budgets_url, params: { budget: { amount: 1200.00, category_id: category.id, period: "yearly", start_date: "2026-01-01" } }
    end

    assert_redirected_to budget_url(Budget.last)
    assert_equal "yearly", Budget.last.period
    assert_equal Date.new(2026, 1, 1), Budget.last.start_date
  end

  test "should show budget" do
    get budget_url(@budget)
    assert_response :success
  end

  test "should get edit" do
    get edit_budget_url(@budget)
    assert_response :success
  end

  test "should update budget" do
    patch budget_url(@budget), params: { budget: { amount: 600.00, category_id: @budget.category_id, period: @budget.period } }
    assert_redirected_to budget_url(@budget)
  end

  test "should destroy budget" do
    assert_difference("Budget.count", -1) do
      delete budget_url(@budget)
    end

    assert_redirected_to budgets_url
  end

  test "should not allow duplicate category budgets" do
    post budgets_url, params: { budget: { amount: 300.00, category_id: @budget.category_id, period: "monthly" } }
    assert_response :unprocessable_entity
  end
end

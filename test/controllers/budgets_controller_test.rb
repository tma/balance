require "test_helper"

class BudgetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @budget = budgets(:groceries_budget)
  end

  test "should get index" do
    get budgets_url
    assert_response :success
  end

  test "should get new" do
    get new_budget_url
    assert_response :success
  end

  test "should create budget" do
    # Create a new category to avoid uniqueness constraint
    category = Category.create!(name: "entertainment", category_type: "expense")
    assert_difference("Budget.count") do
      post budgets_url, params: { budget: { amount: 200.00, category_id: category.id, month: 2, year: 2026 } }
    end

    assert_redirected_to budget_url(Budget.last)
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
    patch budget_url(@budget), params: { budget: { amount: @budget.amount, category_id: @budget.category_id, month: @budget.month, year: @budget.year } }
    assert_redirected_to budget_url(@budget)
  end

  test "should destroy budget" do
    assert_difference("Budget.count", -1) do
      delete budget_url(@budget)
    end

    assert_redirected_to budgets_url
  end
end

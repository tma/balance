require "test_helper"

class Admin::CategoriesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @category = categories(:salary)
  end

  test "should get index" do
    get admin_categories_url
    assert_response :success
  end

  test "should get new" do
    get new_admin_category_url
    assert_response :success
  end

  test "should create category" do
    assert_difference("Category.count") do
      post admin_categories_url, params: { category: { category_type: "expense", name: "travel" } }
    end

    assert_redirected_to admin_category_url(Category.last)
  end

  test "should show category" do
    get admin_category_url(@category)
    assert_response :success
  end

  test "should get edit" do
    get edit_admin_category_url(@category)
    assert_response :success
  end

  test "should update category" do
    patch admin_category_url(@category), params: { category: { category_type: @category.category_type, name: @category.name } }
    assert_redirected_to admin_category_url(@category)
  end

  test "should update expense category essentiality and return to cost of living" do
    category = categories(:groceries)

    patch admin_category_url(category), params: {
      category: { essentiality: "mixed" },
      return_to: "cost_of_living"
    }

    assert_redirected_to cash_flow_url(view: "cost_of_living")
    assert category.reload.essentiality_mixed?
  end

  test "should update all expense category essentialities in one request" do
    groceries = categories(:groceries)
    entertainment = categories(:entertainment)

    assert_enqueued_with(job: ExpenseProfileDetectionJob) do
      patch update_essentialities_admin_categories_url, params: {
        essentialities: {
          groceries.id => "mixed",
          entertainment.id => "excluded"
        }
      }
    end

    assert_redirected_to cash_flow_url(view: "cost_of_living")
    assert groceries.reload.essentiality_mixed?
    assert entertainment.reload.essentiality_excluded?
  end

  test "should destroy category" do
    # Create a new category to destroy (not used by transactions/budgets)
    category = Category.create!(name: "unused_category", category_type: "expense")
    assert_difference("Category.count", -1) do
      delete admin_category_url(category)
    end

    assert_redirected_to admin_categories_url
  end

  test "destroying an unused category removes its generated profiles" do
    category = Category.create!(name: "profile_only_category", category_type: "expense")
    ExpenseProfile.create!(
      category: category,
      merchant_pattern: "Generated Pattern",
      source: "machine",
      status: "suggested"
    )

    assert_difference([ "Category.count", "ExpenseProfile.count" ], -1) do
      delete admin_category_url(category)
    end

    assert_redirected_to admin_categories_url
  end
end

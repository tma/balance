require "test_helper"

class Admin::CategoriesControllerTest < ActionDispatch::IntegrationTest
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
      post admin_categories_url, params: { category: { category_type: "expense", name: "entertainment" } }
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

  test "should destroy category" do
    # Create a new category to destroy (not used by transactions/budgets)
    category = Category.create!(name: "travel", category_type: "expense")
    assert_difference("Category.count", -1) do
      delete admin_category_url(category)
    end

    assert_redirected_to admin_categories_url
  end
end

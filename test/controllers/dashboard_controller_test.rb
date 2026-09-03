require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "should get cash_flow" do
    get cash_flow_url
    assert_response :success
  end

  test "should get cost of living cash flow" do
    mixed = Category.create!(name: "Mixed dashboard costs", category_type: "expense", essentiality: "mixed")
    Transaction.create!(
      account: accounts(:checking_account),
      category: mixed,
      amount: 50,
      transaction_type: "expense",
      date: 1.month.ago.to_date,
      description: "MIXED DASHBOARD COST"
    )

    get cash_flow_url(view: "cost_of_living")

    assert_response :success
    assert_select "p", text: /Minimum monthly income required/
    assert_select "h2", text: /Classify expense categories/
    assert_select "a[href*='category_id=']", minimum: 1
    assert_select "form[action='#{detect_expense_profiles_path}'] button", text: "Refresh Suggestions"
    assert_select "input[type='submit'][value='Save Categories']"
    assert_select "option", text: "Mixed", minimum: 1
    assert_select "p", text: /profiles can override it/
    assert_select "a[href=?]", transactions_path(cost_of_living: "mixed_remainder"), text: "Mixed Remainder (Not Included)"
    assert_select "label.sr-only", text: "Data Complete Through"
    assert_select "select[name='through'][onchange='this.form.requestSubmit()']"
    assert_select "select[name='through'] option", text: /\A(?:January|February|March|April|May|June|July|August|September|October|November|December) \d{4}\z/, minimum: 1
    assert_select "select[name='through'] option", text: /Automatic/, count: 0
    assert_select "input[type='submit'][value='Apply']", count: 0
    assert_select "div.flex.items-center.gap-2" do
      assert_select "form[action='#{cash_flow_path}'][method='get']"
      assert_select "form[action='#{detect_expense_profiles_path}'] button", text: "Refresh Suggestions"
    end
  end

  test "cost of living supports an upgraded database with unclassified categories" do
    Category.expense.update_all(essentiality: nil)

    get cash_flow_url(view: "cost_of_living")

    assert_response :success
    assert_select "strong", text: "Setup required."
    assert_select "div", text: /existing transactions are unchanged/
  end

  test "cost of living honors a manual through month in the URL" do
    get cash_flow_url(view: "cost_of_living", through: "2026-06")

    assert_response :success
    assert_select "p", text: /Data window: July 2025–June 2026/
    assert_select "option[selected][value='2026-06']", text: "June 2026"
  end

  test "cost of living rejects a current or future through month" do
    get cash_flow_url(view: "cost_of_living", through: Date.current.strftime("%Y-%m"))

    assert_response :bad_request
  end

  test "manual cost of living cutoff shows Auto link before the selector" do
    get cash_flow_url(view: "cost_of_living", through: "2026-06")

    assert_select "div.flex.items-center.gap-2" do
      assert_select "a[href='#{cash_flow_path(view: "cost_of_living")}']", text: "Auto"
      assert_select "select[name='through']"
    end
  end

  test "should get net_worth" do
    get net_worth_url
    assert_response :success
  end

  test "root should redirect to cash_flow" do
    get root_url
    assert_response :success
  end
end

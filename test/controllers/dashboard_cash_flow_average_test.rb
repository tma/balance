require "test_helper"

class DashboardCashFlowAverageTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:checking_account)
    @expense_category = categories(:groceries)
    @income_category = categories(:salary)
  end

  # Helper to create an expense transaction for a given month, bypassing callbacks
  def create_expense(year, month, amount)
    Transaction.insert({
      account_id: @account.id,
      category_id: @expense_category.id,
      amount: amount,
      amount_in_default_currency: amount,
      transaction_type: "expense",
      date: Date.new(year, month, 15),
      description: "Test expense #{year}-#{month}",
      exchange_rate: 1.0,
      created_at: Time.current,
      updated_at: Time.current
    })
  end

  # Helper to create an income transaction for a given month, bypassing callbacks
  def create_income(year, month, amount)
    Transaction.insert({
      account_id: @account.id,
      category_id: @income_category.id,
      amount: amount,
      amount_in_default_currency: amount,
      transaction_type: "income",
      date: Date.new(year, month, 15),
      description: "Test income #{year}-#{month}",
      exchange_rate: 1.0,
      created_at: Time.current,
      updated_at: Time.current
    })
  end

  # --- Unit-style tests for average and anomaly calculation ---

  test "trailing average with 12 months of prior data" do
    # Create 12 months of expense data in 2025 (Jan-Dec)
    (1..12).each { |m| create_expense(2025, m, 1000) }
    # Create income so months are not empty
    (1..12).each { |m| create_income(2025, m, 5000) }

    # Create January 2026 with higher expenses
    create_expense(2026, 1, 1500)
    create_income(2026, 1, 5000)

    get cash_flow_url(year: 2026)
    assert_response :success

    controller = @controller
    # Access the monthly data through the assigns
    monthly_data = controller.instance_variable_get(:@monthly_data)
    january = monthly_data.find { |m| m[:month] == 1 }

    assert_not_nil january[:trailing_average], "January should have a trailing average"
    assert_in_delta 1000.0, january[:trailing_average], 0.01, "Average of 12 months at 1000 each should be 1000"
    assert_equal 50.0, january[:delta_percent], "1500 vs 1000 average = 50% above"
    assert january[:anomaly], "50% above average should be flagged as anomaly"
  end

  test "trailing average with fewer than 12 months of prior data" do
    # Only create 3 months of prior data (Oct, Nov, Dec 2025)
    (10..12).each { |m| create_expense(2025, m, 800) }
    (10..12).each { |m| create_income(2025, m, 5000) }

    # Create January 2026
    create_expense(2026, 1, 900)
    create_income(2026, 1, 5000)

    get cash_flow_url(year: 2026)
    assert_response :success

    monthly_data = @controller.instance_variable_get(:@monthly_data)
    january = monthly_data.find { |m| m[:month] == 1 }

    assert_not_nil january[:trailing_average], "Should compute average with partial data"
    assert_in_delta 800.0, january[:trailing_average], 0.01, "Average of 3 months at 800 each should be 800"
  end

  test "no trailing data shows nil average" do
    # Only create data for January 2026, with no prior months
    create_expense(2026, 1, 1000)
    create_income(2026, 1, 5000)

    get cash_flow_url(year: 2026)
    assert_response :success

    monthly_data = @controller.instance_variable_get(:@monthly_data)
    january = monthly_data.find { |m| m[:month] == 1 }

    assert_nil january[:trailing_average], "No trailing data should yield nil average"
    assert_nil january[:delta_percent]
    assert_not january[:anomaly]
  end

  test "anomaly threshold: 19% above average is not flagged" do
    (1..12).each { |m| create_expense(2025, m, 1000) }
    (1..12).each { |m| create_income(2025, m, 5000) }

    # 1190 is 19% above 1000 — should not be flagged
    create_expense(2026, 1, 1190)
    create_income(2026, 1, 5000)

    get cash_flow_url(year: 2026)
    assert_response :success

    monthly_data = @controller.instance_variable_get(:@monthly_data)
    january = monthly_data.find { |m| m[:month] == 1 }

    assert_not january[:anomaly], "19% above average should not be flagged"
    assert january[:delta_percent] < 20.0
  end

  test "anomaly threshold: exactly 20% above average is flagged" do
    (1..12).each { |m| create_expense(2025, m, 1000) }
    (1..12).each { |m| create_income(2025, m, 5000) }

    # 1200 is exactly 20% above 1000
    create_expense(2026, 1, 1200)
    create_income(2026, 1, 5000)

    get cash_flow_url(year: 2026)
    assert_response :success

    monthly_data = @controller.instance_variable_get(:@monthly_data)
    january = monthly_data.find { |m| m[:month] == 1 }

    assert january[:anomaly], "Exactly 20% above average should be flagged"
    assert_in_delta 20.0, january[:delta_percent], 0.1
  end

  test "future months have nil average and no anomaly" do
    # Create some historical data
    (1..12).each { |m| create_expense(2025, m, 1000) }
    (1..12).each { |m| create_income(2025, m, 5000) }

    # Request a year far in the future where all months are future
    get cash_flow_url(year: 2030)
    assert_response :success

    monthly_data = @controller.instance_variable_get(:@monthly_data)
    monthly_data.each do |month|
      assert_nil month[:trailing_average], "Future month #{month[:month]} should have nil average"
      assert_not month[:anomaly], "Future month #{month[:month]} should not be flagged"
    end
  end

  test "months with no activity have nil average" do
    # Request a year with zero transactions
    get cash_flow_url(year: 2020)
    assert_response :success

    monthly_data = @controller.instance_variable_get(:@monthly_data)
    monthly_data.each do |month|
      assert_nil month[:trailing_average], "Month #{month[:month]} with no data should have nil average"
      assert_not month[:anomaly]
    end
  end

  # --- View rendering tests ---

  test "yearly view shows High badge for anomalous month" do
    # Create 12 months of baseline at 1000
    (1..12).each { |m| create_expense(2025, m, 1000) }
    (1..12).each { |m| create_income(2025, m, 5000) }

    # January 2026 at 1500 (50% above) — should get "High" badge
    create_expense(2026, 1, 1500)
    create_income(2026, 1, 5000)

    get cash_flow_url(year: 2026)
    assert_response :success

    assert_select "span.mr-1", text: "High"
  end

  test "yearly view does not show High badge when below threshold" do
    (1..12).each { |m| create_expense(2025, m, 1000) }
    (1..12).each { |m| create_income(2025, m, 5000) }

    # January 2026 at 1100 (10% above) — should NOT get "High" badge
    create_expense(2026, 1, 1100)
    create_income(2026, 1, 5000)

    get cash_flow_url(year: 2026)
    assert_response :success

    assert_select "span.mr-1", text: "High", count: 0
  end

  # --- Bar chart rendering tests ---

  test "yearly view renders bar chart SVG" do
    create_expense(2026, 1, 1000)
    create_income(2026, 1, 5000)

    get cash_flow_url(year: 2026)
    assert_response :success

    # Chart SVG should be present with bars
    assert_select "svg rect[fill='#60a5fa']", minimum: 1, message: "Should have income bar"
    assert_select "svg rect[fill='#fb7185']", minimum: 1, message: "Should have expense bar"
  end

  test "yearly view renders trailing average curve when data exists" do
    (1..12).each { |m| create_expense(2025, m, 1000) }
    (1..12).each { |m| create_income(2025, m, 5000) }
    create_expense(2026, 1, 1200)
    create_income(2026, 1, 5000)
    create_expense(2026, 2, 1100)
    create_income(2026, 2, 5000)

    get cash_flow_url(year: 2026)
    assert_response :success

    assert_select "svg path", minimum: 1, message: "Should render trailing average curve"
  end

  test "monthly view does not render bar chart" do
    get cash_flow_url(year: 2026, month: 1)
    assert_response :success

    # The bar chart uses data-bar-group="cf0" — should not be in monthly view
    assert_select "rect[data-bar-group='cf0']", count: 0
  end
end

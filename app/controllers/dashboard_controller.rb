class DashboardController < ApplicationController
  def home
    @default_currency = Currency.default_code
    @valuation_date = default_valuation_date

    load_asset_groups_with_valuations

    @net_worth = calculate_totals_for_month(@valuation_date)
    @net_worth_change = calculate_net_worth_change(@valuation_date)
    @group_totals = calculate_group_totals

    # Cash flow for current and 2 previous months
    @monthly_cash_flow = calculate_monthly_data(3)

    # Coverage gaps for data health panel
    @coverage_gaps = Account.active.filter_map(&:coverage_analysis).reject { |c| c[:complete?] }
  end

  def cash_flow
    @default_currency = Currency.default_code

    # Parse year/month from params
    @selected_year = (params[:year] || Date.current.year).to_i
    @selected_month = params[:month]&.to_i  # nil = full year

    # Year range for navigation (based on available transactions)
    @min_year = Transaction.minimum(:date)&.year || Date.current.year
    @max_year = Date.current.year

    # Monthly data for selected calendar year (Jan-Dec)
    @monthly_data = calculate_monthly_data_for_year(@selected_year)
    @year_totals = calculate_year_totals(@selected_year)

    # Period totals (respects month filter)
    @period_totals = calculate_period_totals(@selected_year, @selected_month)

    # Category breakdowns for donut chart
    @income_by_category = calculate_category_breakdown(:income, @selected_year, @selected_month)
    @expense_by_category = calculate_category_breakdown(:expense, @selected_year, @selected_month)

    # Combined categories with spending and budgets (sorted by % descending)
    @category_spending = build_category_spending(@selected_year, @selected_month)
    @income_category_spending = build_income_category_spending(@selected_year, @selected_month)

    # Budgets separated by period (kept for reference)
    @monthly_budgets = Budget.monthly.includes(:category).order("categories.name")
    @yearly_budgets = Budget.yearly.includes(:category).order("categories.name")
    @budget_year = @selected_year
    @budget_month = @selected_month || Date.current.month
  end

  def net_worth
    @default_currency = Currency.default_code
    @valuation_date = params[:month].present? ? Date.parse("#{params[:month]}-01").end_of_month : default_valuation_date
    @current_month = @valuation_date.strftime("%Y-%m")

    load_asset_groups_with_valuations

    @net_worth = calculate_totals_for_month(@valuation_date)
    @net_worth_change = calculate_net_worth_change(@valuation_date)
    @totals = @net_worth
    @group_totals = calculate_group_totals

    # Historical data for bar chart (12 months ending at valuation_date)
    @history_months = (0..11).map { |i| (@valuation_date - i.months).end_of_month }.reverse
    @history_by_group = build_history_by_group(@history_months)

    # Quarterly history (12 quarters = 3 years, using end of quarter)
    @history_quarters = (0..11).map { |i| (@valuation_date - (i * 3).months).end_of_quarter }.reverse
    @history_by_group_quarterly = build_history_by_group(@history_quarters)

    # Assets with broker positions for badge display
    @broker_asset_ids = BrokerPosition.where.not(asset_id: nil).pluck(:asset_id).uniq.to_set
  end

  private

  # Default to last complete month (end of previous month)
  def default_valuation_date
    (Date.current.beginning_of_month - 1.day).end_of_month
  end

  # Load asset groups with their assets and build valuations lookup
  def load_asset_groups_with_valuations
    @asset_groups = AssetGroup.includes(assets: [ :asset_type, :asset_valuations ]).order(:position, :name)
    @valuations_by_asset = {}
    Asset.includes(:asset_type, :asset_valuations).each do |asset|
      valuation = asset.asset_valuations.find { |v| v.date == @valuation_date }
      @valuations_by_asset[asset.id] = valuation
    end
  end

  # Calculate net worth change from previous month
  def calculate_net_worth_change(date)
    previous_month = date - 1.month
    current = calculate_totals_for_month(date)[:net_worth]
    previous = calculate_totals_for_month(previous_month)[:net_worth]
    current - previous
  end

  def build_history_by_group(dates)
    # Returns: { group_id => { date => net_value } }
    # Uses net values (assets - liabilities) per group
    history = Hash.new { |h, k| h[k] = {} }

    @asset_groups.each do |group|
      dates.each do |date|
        total = 0
        group.assets.each do |asset|
          valuation = asset.asset_valuations.find { |v| v.date == date }
          next unless valuation
          value = valuation.value_in_default_currency || 0
          total += asset.asset_type.is_liability ? -value : value
        end
        history[group.id][date] = total
      end
    end

    history
  end

  # Calculate net value per asset group using valuations lookup
  # Includes active and archived assets that have a valuation for the month
  def calculate_group_totals
    totals = {}
    @asset_groups.each do |group|
      net = 0
      group.assets.each do |asset|
        valuation = @valuations_by_asset[asset.id]
        next unless valuation
        value = valuation.value_in_default_currency || 0
        net += asset.asset_type.is_liability ? -value : value
      end
      totals[group.id] = net
    end
    totals
  end

  def calculate_totals_for_month(date)
    month_end = date.end_of_month

    total_assets = 0
    total_liabilities = 0

    Asset.includes(:asset_type, :asset_valuations).each do |asset|
      valuation = asset.asset_valuations.find { |v| v.date == month_end }
      next unless valuation

      value = valuation.value_in_default_currency || 0
      if asset.asset_type.is_liability
        total_liabilities += value
      else
        total_assets += value
      end
    end

    {
      assets: total_assets,
      liabilities: total_liabilities,
      net_worth: total_assets - total_liabilities
    }
  end

  def calculate_monthly_data(months)
    data = []
    current = Date.current.beginning_of_month

    months.times do |i|
      month_start = current - i.months
      year = month_start.year
      month = month_start.month

      # Use amount_in_default_currency for consistent totals
      income = Transaction.income.in_month(year, month).sum(:amount_in_default_currency) || 0
      expenses = Transaction.expense.in_month(year, month).sum(:amount_in_default_currency) || 0
      net = income - expenses
      saving_rate = income > 0 ? ((income - expenses) / income * 100).round(1) : 0

      data << {
        date: month_start,
        year: year,
        month: month,
        month_name: month_start.strftime("%B %Y"),
        income: income,
        expenses: expenses,
        net: net,
        saving_rate: saving_rate
      }
    end

    data
  end

  def calculate_monthly_data_for_year(year)
    (1..12).map do |month|
      month_start = Date.new(year, month, 1)
      income = Transaction.income.in_month(year, month).sum(:amount_in_default_currency) || 0
      expenses = Transaction.expense.in_month(year, month).sum(:amount_in_default_currency) || 0
      net = income - expenses
      saving_rate = income > 0 ? ((net / income) * 100).round(1) : 0

      {
        date: month_start,
        year: year,
        month: month,
        month_name: month_start.strftime("%B %Y"),
        month_abbr: Date::ABBR_MONTHNAMES[month],
        income: income,
        expenses: expenses,
        net: net,
        saving_rate: saving_rate,
        is_future: month_start > Date.current
      }
    end
  end

  def calculate_year_totals(year)
    income = Transaction.income.in_year(year).sum(:amount_in_default_currency) || 0
    expenses = Transaction.expense.in_year(year).sum(:amount_in_default_currency) || 0
    net = income - expenses
    saving_rate = income > 0 ? ((net / income) * 100).round(1) : 0

    { income: income, expenses: expenses, net: net, saving_rate: saving_rate }
  end

  def calculate_period_totals(year, month = nil)
    if month
      income = Transaction.income.in_month(year, month).sum(:amount_in_default_currency) || 0
      expenses = Transaction.expense.in_month(year, month).sum(:amount_in_default_currency) || 0
    else
      income = Transaction.income.in_year(year).sum(:amount_in_default_currency) || 0
      expenses = Transaction.expense.in_year(year).sum(:amount_in_default_currency) || 0
    end
    net = income - expenses
    saving_rate = income > 0 ? ((net / income) * 100).round(1) : 0

    { income: income, expenses: expenses, net: net, saving_rate: saving_rate }
  end

  def calculate_category_breakdown(type, year, month = nil)
    scope = type == :income ? Transaction.income : Transaction.expense
    scope = month ? scope.in_month(year, month) : scope.in_year(year)

    scope.joins(:category)
         .group("categories.id", "categories.name")
         .sum(:amount_in_default_currency)
         .map { |(id, name), amount| { id: id, name: name, amount: amount } }
         .sort_by { |c| -c[:amount] }
  end

  # Build combined category spending with budget info and percentage of total expenses
  # Returns array of { category:, spent:, budget:, budget_amount:, pct: } for all categories
  # that have either transactions or budgets in the period, sorted by percentage descending
  def build_category_spending(year, month = nil)
    # Get all expense transactions grouped by category for the period
    scope = month ? Transaction.expense.in_month(year, month) : Transaction.expense.in_year(year)
    spending_by_category = scope.joins(:category)
                                .group("categories.id")
                                .sum(:amount_in_default_currency)

    # Get relevant budgets (monthly if month selected, yearly if full year)
    budgets = month ? Budget.monthly.includes(:category) : Budget.yearly.includes(:category)
    budgets_by_category = budgets.index_by(&:category_id)

    # Collect all relevant category IDs
    category_ids = (spending_by_category.keys + budgets_by_category.keys).uniq
    categories = Category.where(id: category_ids).index_by(&:id)

    total_expenses = spending_by_category.values.sum

    # Build result array
    result = category_ids.map do |cat_id|
      category = categories[cat_id]
      next unless category

      spent = spending_by_category[cat_id] || 0
      budget = budgets_by_category[cat_id]
      pct = total_expenses > 0 ? (spent.to_f / total_expenses * 100).round : 0

      {
        category: category,
        spent: spent,
        budget: budget,
        budget_amount: budget&.amount,
        pct: pct
      }
    end.compact

    # Sort by percentage descending (highest spending first), tiebreak by amount
    result.sort_by { |r| [-r[:pct], -r[:spent]] }
  end

  # Build income category data with percentage of total income
  # Returns array of { category:, earned:, pct: } sorted by percentage descending
  def build_income_category_spending(year, month = nil)
    scope = month ? Transaction.income.in_month(year, month) : Transaction.income.in_year(year)
    income_by_category = scope.joins(:category)
                              .group("categories.id")
                              .sum(:amount_in_default_currency)

    return [] if income_by_category.empty?

    total_income = income_by_category.values.sum
    categories = Category.where(id: income_by_category.keys).index_by(&:id)

    result = income_by_category.map do |cat_id, earned|
      category = categories[cat_id]
      next unless category

      pct = total_income > 0 ? (earned.to_f / total_income * 100).round : 0

      {
        category: category,
        earned: earned,
        pct: pct
      }
    end.compact

    result.sort_by { |r| [-r[:pct], -r[:earned]] }
  end
end

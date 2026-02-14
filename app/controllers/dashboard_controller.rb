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

    # Parse year/month from params (needed for navigation in all views)
    @selected_year = (params[:year] || Date.current.year).to_i
    @selected_month = params[:month]&.to_i  # nil = full year

    # Year range for navigation (based on available transactions)
    @min_year = Transaction.minimum(:date)&.year || Date.current.year
    @max_year = Date.current.year

    # Handle projected view
    if params[:view] == "projected"
      @projection = calculate_annual_projection
      render "dashboard/cash_flow_projected"
      return
    end

    # Monthly data for selected calendar year (Jan-Dec)
    @monthly_data = calculate_monthly_data_for_year(@selected_year)
    enrich_monthly_data_with_averages(@monthly_data, @selected_year)
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

  # Compute signed income/expense totals based on category type (not transaction type).
  # For income categories: income transactions add, expense transactions subtract.
  # For expense categories: expense transactions add, income transactions subtract.
  # This ensures refunds on expense categories reduce expenses rather than inflating income.
  def signed_sum_by_category_type(scope)
    signed = scope.joins(:category)
                  .group("categories.category_type")
                  .sum(Transaction.signed_amount_by_category_type_sql)
    income = signed["income"] || 0
    expenses = signed["expense"] || 0
    { income: income, expenses: expenses }
  end

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

      # Use category type for income/expense classification (not transaction type)
      totals = signed_sum_by_category_type(Transaction.in_month(year, month))
      income = totals[:income]
      expenses = totals[:expenses]
      net = income - expenses
      saving_rate = income > 0 ? ((net / income) * 100).round(1) : 0

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
      totals = signed_sum_by_category_type(Transaction.in_month(year, month))
      income = totals[:income]
      expenses = totals[:expenses]
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
    totals = signed_sum_by_category_type(Transaction.in_year(year))
    income = totals[:income]
    expenses = totals[:expenses]
    net = income - expenses
    saving_rate = income > 0 ? ((net / income) * 100).round(1) : 0

    { income: income, expenses: expenses, net: net, saving_rate: saving_rate }
  end

  def calculate_period_totals(year, month = nil)
    scope = month ? Transaction.in_month(year, month) : Transaction.in_year(year)
    totals = signed_sum_by_category_type(scope)
    income = totals[:income]
    expenses = totals[:expenses]
    net = income - expenses
    saving_rate = income > 0 ? ((net / income) * 100).round(1) : 0

    { income: income, expenses: expenses, net: net, saving_rate: saving_rate }
  end

  # Enrich monthly data with trailing 12-month average expenses and anomaly flags.
  # For each month, looks back up to 12 months (excluding the month itself) to compute
  # the average expense baseline. Flags months where expenses exceed the average by >= 20%.
  # Only months with actual expense transactions contribute to the average.
  def enrich_monthly_data_with_averages(monthly_data, year)
    # Batch-fetch all monthly expense totals for the full lookback window in a single query.
    # The earliest trailing month needed is 12 months before January of the selected year.
    # Uses category_type to determine expenses (not transaction_type), with signed amounts
    # so that refunds on expense categories reduce the expense total.
    lookback_start = Date.new(year, 1, 1) - 12.months
    lookback_end = Date.new(year, 12, 31)

    expense_totals_by_month = Transaction
      .joins(:category)
      .where(date: lookback_start..lookback_end)
      .where(categories: { category_type: "expense" })
      .group("strftime('%Y', date)", "strftime('%m', date)")
      .sum(Transaction.signed_amount_sql("expense"))
      .transform_keys { |y, m| [ y.to_i, m.to_i ] }

    monthly_data.each do |month|
      if month[:is_future] || (month[:income] == 0 && month[:expenses] == 0)
        month[:trailing_average] = nil
        month[:delta_percent] = nil
        month[:anomaly] = false
        next
      end

      # Collect trailing 12 months of expenses (excluding current month).
      # Only months that have expense transactions contribute to the average.
      trailing_expenses = []
      12.times do |i|
        d = Date.new(year, month[:month], 1) - (i + 1).months
        total = expense_totals_by_month[[ d.year, d.month ]]
        trailing_expenses << total if total
      end

      if trailing_expenses.empty?
        month[:trailing_average] = nil
        month[:delta_percent] = nil
        month[:anomaly] = false
      else
        average = trailing_expenses.sum.to_f / trailing_expenses.size
        month[:trailing_average] = average.round(2)

        if average > 0
          delta = ((month[:expenses] - average) / average * 100).round(1)
          month[:delta_percent] = delta
          month[:anomaly] = delta >= 20.0
        else
          month[:delta_percent] = nil
          month[:anomaly] = false
        end
      end
    end
  end

  def calculate_category_breakdown(type, year, month = nil)
    scope = month ? Transaction.in_month(year, month) : Transaction.in_year(year)

    # Filter by category type and compute signed amounts
    positive_type = type == :income ? "income" : "expense"
    scope.joins(:category)
         .where(categories: { category_type: positive_type })
         .group("categories.id", "categories.name")
         .sum(Transaction.signed_amount_sql(positive_type))
         .map { |(id, name), amount| { id: id, name: name, amount: amount } }
         .select { |c| c[:amount] != 0 }
         .sort_by { |c| -c[:amount] }
  end

  # Build combined category spending with budget info and percentage of total expenses
  # Returns array of { category:, spent:, budget:, budget_amount:, pct: } for all categories
  # that have either transactions or budgets in the period, sorted by percentage descending
  def build_category_spending(year, month = nil)
    # Get all transactions on expense categories, with signed amounts
    # (expense transactions add to spent, income/refund transactions subtract)
    scope = month ? Transaction.in_month(year, month) : Transaction.in_year(year)
    spending_by_category = scope.joins(:category)
                                .where(categories: { category_type: "expense" })
                                .group("categories.id")
                                .sum(Transaction.signed_amount_sql("expense"))

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
    result.sort_by { |r| [ -r[:pct], -r[:spent] ] }
  end

  # Build income category data with percentage of total income
  # Returns array of { category:, earned:, pct: } sorted by percentage descending
  def build_income_category_spending(year, month = nil)
    # Get all transactions on income categories, with signed amounts
    # (income transactions add to earned, expense transactions subtract)
    scope = month ? Transaction.in_month(year, month) : Transaction.in_year(year)
    income_by_category = scope.joins(:category)
                              .where(categories: { category_type: "income" })
                              .group("categories.id")
                              .sum(Transaction.signed_amount_sql("income"))

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

    result.sort_by { |r| [ -r[:pct], -r[:earned] ] }
  end

  # ── Annual Projection ──────────────────────────────────────────────────

  def calculate_annual_projection
    active_months = Transaction.distinct.count("strftime('%Y-%m', date)")
    total_transactions = Transaction.count

    return nil if active_months == 0

    categories_data = calculate_projected_categories(active_months)

    income_categories = categories_data.select { |c| c[:category_type] == "income" }
    expense_categories = categories_data.select { |c| c[:category_type] == "expense" }

    total_income = income_categories.sum { |c| c[:annual] }
    total_expenses = expense_categories.sum { |c| c[:annual] }
    net = total_income - total_expenses
    saving_rate = total_income > 0 ? ((net / total_income) * 100).round(1) : 0

    # Build category breakdown data for donut chart (reuse existing helper format)
    income_by_category = income_categories.map { |c| { id: c[:id], name: c[:name], amount: c[:annual] } }
    expense_by_category = expense_categories.map { |c| { id: c[:id], name: c[:name], amount: c[:annual] } }

    # Budget comparison: annualize all budgets for projection context
    budgets_by_category = Budget.includes(:category).index_by(&:category_id)

    expense_categories_with_budgets = expense_categories.map do |cat|
      budget = budgets_by_category[cat[:id]]
      annual_budget = if budget
        budget.yearly? ? budget.amount : budget.amount * 12
      end
      cat.merge(budget: budget, annual_budget: annual_budget)
    end

    income_categories_with_budgets = income_categories

    {
      active_months: active_months,
      total_transactions: total_transactions,
      date_range: {
        from: Transaction.minimum(:date),
        to: Transaction.maximum(:date)
      },
      income: total_income,
      expenses: total_expenses,
      net: net,
      saving_rate: saving_rate,
      monthly_income: total_income / 12.0,
      monthly_expenses: total_expenses / 12.0,
      monthly_net: net / 12.0,
      income_categories: income_categories_with_budgets.sort_by { |c| -c[:annual] },
      expense_categories: expense_categories_with_budgets.sort_by { |c| -c[:annual] },
      income_by_category: income_by_category,
      expense_by_category: expense_by_category
    }
  end

  def calculate_projected_categories(active_months)
    # Get monthly totals per category, using signed amounts by category type.
    # Groups by (category_id, year-month) so we can compute per-month variability.
    monthly_totals_raw = Transaction.joins(:category)
      .group(
        "transactions.category_id",
        "categories.name",
        "categories.category_type",
        "strftime('%Y-%m', date)"
      )
      .sum(Transaction.signed_amount_by_category_type_sql)

    # Reorganize into { category_id => { meta + monthly_totals hash } }
    categories = {}
    monthly_totals_raw.each do |(cat_id, cat_name, cat_type, _year_month), amount|
      categories[cat_id] ||= {
        id: cat_id, name: cat_name, category_type: cat_type,
        monthly_totals: Hash.new(0)
      }
      categories[cat_id][:monthly_totals][_year_month] = amount
    end

    categories.values.map do |cat|
      months_with_data = cat[:monthly_totals].size
      totals = cat[:monthly_totals].values

      # Pad with zeros for active months where this category had no transactions
      padded = totals + Array.new([ active_months - months_with_data, 0 ].max, 0)

      total = padded.sum
      monthly_avg = total.to_f / active_months
      annual = monthly_avg * 12

      # Coefficient of variation for confidence indicator
      cv = calculate_cv(padded, monthly_avg)

      confidence = if cv <= 0.5
        :stable
      elsif cv <= 1.0
        :variable
      else
        :erratic
      end

      {
        id: cat[:id],
        name: cat[:name],
        category_type: cat[:category_type],
        monthly_avg: monthly_avg.round(2),
        annual: annual.round(2),
        cv: cv,
        confidence: confidence,
        months_with_data: months_with_data
      }
    end
  end

  def calculate_cv(values, mean)
    return 0.0 if mean == 0 || values.size <= 1

    variance = values.sum { |v| (v - mean)**2 } / values.size.to_f
    stddev = Math.sqrt(variance)
    (stddev / mean.abs).round(2)
  end
end

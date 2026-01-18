class DashboardController < ApplicationController
  def home
    @default_currency = Currency.default&.code || "USD"

    # Net worth data for latest complete month (last month end)
    @valuation_date = (Date.current.beginning_of_month - 1.day).end_of_month
    @asset_groups = AssetGroup.includes(assets: [ :asset_type, :asset_valuations ]).order(:position, :name)

    # Build valuations lookup for current month
    @valuations_by_asset = {}
    Asset.includes(:asset_type, :asset_valuations).each do |asset|
      valuation = asset.asset_valuations.find { |v| v.date == @valuation_date }
      @valuations_by_asset[asset.id] = valuation
    end

    # Net worth calculation
    @net_worth = calculate_net_worth_for_month(@valuation_date)

    # Previous month for comparison
    previous_month = @valuation_date - 1.month
    @previous_net_worth = calculate_net_worth_for_month(previous_month)[:net_worth]
    @net_worth_change = @net_worth[:net_worth] - @previous_net_worth

    # Group totals for donut chart
    @group_totals = {}
    @asset_groups.each do |group|
      net = 0
      group.assets.each do |asset|
        valuation = @valuations_by_asset[asset.id]
        next unless valuation
        value = valuation.value_in_default_currency || 0
        net += asset.asset_type.is_liability ? -value : value
      end
      @group_totals[group.id] = net
    end

    # Cash flow for current and 2 previous months
    @monthly_cash_flow = calculate_monthly_data(3)
  end

  def cash_flow
    @default_currency = Currency.default&.code || "USD"

    # Last 12 months data (including current month) - all in default currency
    @monthly_data = calculate_monthly_data(12)
    @twelve_month_totals = calculate_twelve_month_totals

    # Budgets separated by period
    @monthly_budgets = Budget.monthly.includes(:category).order("categories.name")
    @yearly_budgets = Budget.yearly.includes(:category).order("categories.name")

    # Recent transactions
    @recent_transactions = Transaction.includes(:account, :category).recent(5)
  end

  def net_worth
    @default_currency = Currency.default&.code || "USD"

    # Current viewing month (default to last complete month)
    if params[:month].present?
      @valuation_date = Date.parse("#{params[:month]}-01").end_of_month
    else
      @valuation_date = (Date.current.beginning_of_month - 1.day).end_of_month
    end
    @current_month = @valuation_date.strftime("%Y-%m")

    # Asset groups with their assets
    @asset_groups = AssetGroup.includes(assets: [ :asset_type, :asset_valuations ]).order(:position, :name)

    # Build valuations lookup for selected month
    @valuations_by_asset = {}
    Asset.includes(:asset_type, :asset_valuations).each do |asset|
      valuation = asset.asset_valuations.find { |v| v.date == @valuation_date }
      @valuations_by_asset[asset.id] = valuation
    end

    # Net worth for selected month
    @net_worth = calculate_net_worth_for_month(@valuation_date)

    # Previous month net worth for comparison
    previous_month = @valuation_date - 1.month
    @previous_month_net_worth = calculate_net_worth_for_month(previous_month)[:net_worth]
    @net_worth_change = @net_worth[:net_worth] - @previous_month_net_worth

    # Overall totals for selected month
    @totals = calculate_totals_for_month(@valuation_date)

    # Group totals for selected month
    @group_totals = {}
    @asset_groups.each do |group|
      net = 0
      group.assets.each do |asset|
        valuation = @valuations_by_asset[asset.id]
        next unless valuation
        value = valuation.value_in_default_currency || 0
        net += asset.asset_type.is_liability ? -value : value
      end
      @group_totals[group.id] = net
    end

    # Historical data for bar chart (12 months ending at valuation_date)
    @history_months = (0..11).map { |i| (@valuation_date - i.months).end_of_month }.reverse
    @history_by_group = build_history_by_group(@history_months)

    # Quarterly history (12 quarters = 3 years, using end of quarter)
    @history_quarters = (0..11).map { |i| (@valuation_date - (i * 3).months).end_of_quarter }.reverse
    @history_by_group_quarterly = build_history_by_group(@history_quarters)
  end

  private

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

  def calculate_net_worth_in_default_currency
    cash = Account.sum(:balance_in_default_currency) || 0
    assets_value = Asset.assets_only.sum(:value_in_default_currency) || 0
    liabilities_value = Asset.liabilities_only.sum(:value_in_default_currency) || 0

    {
      cash: cash,
      assets: assets_value,
      liabilities: liabilities_value,
      net_worth: cash + assets_value - liabilities_value
    }
  end

  def calculate_totals_in_default_currency
    total_assets = Asset.assets_only.sum(:value_in_default_currency) || 0
    total_liabilities = Asset.liabilities_only.sum(:value_in_default_currency) || 0

    {
      assets: total_assets,
      liabilities: total_liabilities,
      net: total_assets - total_liabilities
    }
  end

  def calculate_net_worth_for_month(date)
    month_end = date.end_of_month

    assets_value = 0
    liabilities_value = 0

    Asset.includes(:asset_type, :asset_valuations).each do |asset|
      valuation = asset.asset_valuations.find { |v| v.date == month_end }
      next unless valuation

      value = valuation.value_in_default_currency || 0
      if asset.asset_type.is_liability
        liabilities_value += value
      else
        assets_value += value
      end
    end

    {
      cash: 0,
      assets: assets_value,
      liabilities: liabilities_value,
      net_worth: assets_value - liabilities_value
    }
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
      net: total_assets - total_liabilities
    }
  end

  def calculate_previous_month_net_worth
    previous_month = Date.current.end_of_month - 1.month

    # Sum valuations from previous month
    total = 0
    Asset.includes(:asset_type, :asset_valuations).each do |asset|
      valuation = asset.asset_valuations.find { |v| v.date == previous_month }
      next unless valuation

      value = valuation.value_in_default_currency || 0
      if asset.asset_type.is_liability
        total -= value
      else
        total += value
      end
    end

    total
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

  def calculate_twelve_month_totals
    twelve_months_ago = Date.current.beginning_of_month - 11.months

    # Use amount_in_default_currency for consistent totals
    income = Transaction.income.where("date >= ?", twelve_months_ago).sum(:amount_in_default_currency) || 0
    expenses = Transaction.expense.where("date >= ?", twelve_months_ago).sum(:amount_in_default_currency) || 0
    net = income - expenses
    saving_rate = income > 0 ? ((income - expenses) / income * 100).round(1) : 0

    {
      income: income,
      expenses: expenses,
      net: net,
      saving_rate: saving_rate
    }
  end
end

class DashboardController < ApplicationController
  def home
    @default_currency = Currency.default&.code || "USD"
    @valuation_date = default_valuation_date

    load_asset_groups_with_valuations

    @net_worth = calculate_totals_for_month(@valuation_date)
    @net_worth_change = calculate_net_worth_change(@valuation_date)
    @group_totals = calculate_group_totals

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

class DashboardController < ApplicationController
  def cash_flow
    @default_currency = Currency.default&.code || "USD"

    # Last 12 months data (including current month) - all in default currency
    @monthly_data = calculate_monthly_data(12)
    @twelve_month_totals = calculate_twelve_month_totals

    # All budgets (both monthly and yearly)
    @budgets = Budget.includes(:category).order("categories.name")

    # Recent transactions
    @recent_transactions = Transaction.includes(:account, :category).recent(5)
  end

  def net_worth
    @default_currency = Currency.default&.code || "USD"

    # Net worth in default currency only
    @net_worth = calculate_net_worth_in_default_currency

    # Asset groups with their assets
    @asset_groups = AssetGroup.includes(assets: :asset_type).order(:name)

    # Overall totals in default currency
    @totals = calculate_totals_in_default_currency
  end

  private

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
        month_name: month_start.strftime("%b %Y"),
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

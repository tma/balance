class DashboardController < ApplicationController
  def index
    @accounts = Account.includes(:account_type).order(:name)
    @assets = Asset.includes(:asset_type).assets_only.order(:name)
    @liabilities = Asset.includes(:asset_type).liabilities_only.order(:name)

    # Net worth calculations grouped by currency
    @net_worth_by_currency = calculate_net_worth_by_currency

    # Last 12 months data (including current month)
    @monthly_data = calculate_monthly_data(12)
    @twelve_month_totals = calculate_twelve_month_totals

    # Current month budgets with spending
    @budgets = Budget.includes(:category).current_month

    # Recent transactions
    @recent_transactions = Transaction.includes(:account, :category).recent(5)
  end

  private

  def calculate_net_worth_by_currency
    currencies = Currency.pluck(:code)
    result = {}

    currencies.each do |currency|
      cash = Account.by_currency(currency).sum(:balance)
      assets_value = Asset.assets_only.by_currency(currency).sum(:value)
      liabilities_value = Asset.liabilities_only.by_currency(currency).sum(:value)

      next if cash.zero? && assets_value.zero? && liabilities_value.zero?

      result[currency] = {
        cash: cash,
        assets: assets_value,
        liabilities: liabilities_value,
        net_worth: cash + assets_value - liabilities_value
      }
    end

    result
  end

  def calculate_monthly_data(months)
    data = []
    current = Date.current.beginning_of_month

    months.times do |i|
      month_start = current - i.months
      year = month_start.year
      month = month_start.month

      income = Transaction.income.in_month(year, month).sum(:amount)
      expenses = Transaction.expense.in_month(year, month).sum(:amount)
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
    
    income = Transaction.income.where("date >= ?", twelve_months_ago).sum(:amount)
    expenses = Transaction.expense.where("date >= ?", twelve_months_ago).sum(:amount)
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

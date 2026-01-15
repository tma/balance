class DashboardController < ApplicationController
  def index
    @accounts = Account.includes(:account_type).order(:name)
    @assets = Asset.includes(:asset_type).assets_only.order(:name)
    @liabilities = Asset.includes(:asset_type).liabilities_only.order(:name)

    # Net worth calculations grouped by currency
    @net_worth_by_currency = calculate_net_worth_by_currency

    # Current month stats
    @current_year = Date.current.year
    @current_month = Date.current.month
    @monthly_income = Transaction.income.in_month(@current_year, @current_month).sum(:amount)
    @monthly_expenses = Transaction.expense.in_month(@current_year, @current_month).sum(:amount)
    @monthly_net = @monthly_income - @monthly_expenses

    # Current month budgets with spending
    @budgets = Budget.includes(:category).current_month

    # Recent transactions
    @recent_transactions = Transaction.includes(:account, :category).recent(10)
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
end

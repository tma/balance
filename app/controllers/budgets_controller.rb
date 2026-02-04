class BudgetsController < ApplicationController
  before_action :set_budget, only: %i[ show edit update destroy ]

  def index
    @year = params[:year]&.to_i || Date.current.year
    @month = params[:month]&.to_i || Date.current.month
    @current_date = Date.new(@year, @month, 1)

    all_budgets = Budget.includes(:category)

    @monthly_budgets = all_budgets.monthly
                                  .select { |b| b.active_for?(@current_date) }
                                  .sort_by { |b| b.category.name }

    @yearly_budgets = all_budgets.yearly
                                 .select { |b| b.active_for?(@current_date) }
                                 .sort_by { |b| b.category.name }
  end

  def show
    @year = params[:year]&.to_i || Date.current.year
    @month = params[:month]&.to_i || Date.current.month

    # Build historical data for the budget
    @history = build_budget_history(@budget)
  end

  def new
    @budget = Budget.new(period: "monthly")
  end

  def edit
  end

  def create
    @budget = Budget.new(budget_params)
    set_start_date_from_year

    if @budget.save
      redirect_to @budget, notice: "Budget was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @budget.assign_attributes(budget_params)
    set_start_date_from_year

    if @budget.save
      redirect_to @budget, notice: "Budget was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @budget.destroy!
    redirect_to budgets_path, notice: "Budget was successfully destroyed.", status: :see_other
  end

  private

  def set_budget
    @budget = Budget.find(params.expect(:id))
  end

  def budget_params
    params.expect(budget: [ :category_id, :amount, :period, :start_date ])
  end

  def set_start_date_from_year
    if @budget.yearly?
      # For yearly budgets, use the start_year param if provided
      if params[:budget][:start_year].present?
        @budget.start_date = Date.new(params[:budget][:start_year].to_i, 1, 1)
      elsif params[:budget][:start_year] == ""
        @budget.start_date = nil
      end
    else
      # For monthly budgets, use start_month and start_month_year params
      month = params[:budget][:start_month]
      year = params[:budget][:start_month_year]
      
      if month.present? && year.present?
        @budget.start_date = Date.new(year.to_i, month.to_i, 1)
      elsif month.blank? || year.blank?
        @budget.start_date = nil
      end
    end
  end

  def build_budget_history(budget)
    current_date = Date.current

    if budget.monthly?
      # Get all months from start_date (or earliest transaction) to current month
      start_date = budget.start_date || Transaction.minimum(:date) || current_date
      start_month = start_date.beginning_of_month
      end_month = current_date.beginning_of_month
      
      months = []
      date = end_month
      while date >= start_month
        year = date.year
        month = date.month
        spent = budget.spent(year, month)
        months << {
          label: date.strftime("%b %Y"),
          year: year,
          month: month,
          spent: spent,
          budget_amount: budget.amount,
          percentage: budget.amount.positive? ? ((spent / budget.amount) * 100).round(1) : 0,
          over_budget: spent > budget.amount
        }
        date = date.prev_month
      end
      months
    else
      # Get all years from start_date (or earliest transaction) to current year
      start_year = budget.start_date&.year || Transaction.minimum(:date)&.year || current_date.year
      end_year = current_date.year
      
      (start_year..end_year).to_a.reverse.map do |year|
        spent = budget.spent(year, nil)
        {
          label: year.to_s,
          year: year,
          month: nil,
          spent: spent,
          budget_amount: budget.amount,
          percentage: budget.amount.positive? ? ((spent / budget.amount) * 100).round(1) : 0,
          over_budget: spent > budget.amount
        }
      end
    end
  end
end

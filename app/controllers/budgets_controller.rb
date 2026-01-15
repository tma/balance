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
  end

  def new
    @budget = Budget.new(period: "monthly")
  end

  def edit
  end

  def create
    @budget = Budget.new(budget_params)

    if @budget.save
      redirect_to @budget, notice: "Budget was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @budget.update(budget_params)
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
end

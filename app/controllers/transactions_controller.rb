class TransactionsController < ApplicationController
  before_action :set_transaction, only: %i[ show edit update destroy ]

  def index
    @transactions = Transaction.includes(:account, :category).order(date: :desc, created_at: :desc)

    # Date range filtering
    if params[:start_date].present? && params[:end_date].present?
      @start_date = Date.parse(params[:start_date])
      @end_date = Date.parse(params[:end_date])
      @transactions = @transactions.where(date: @start_date..@end_date)
      @filter_mode = :range
    elsif params[:month].present?
      # Month format: "2026-01"
      date = Date.parse("#{params[:month]}-01")
      @current_month = date
      @transactions = @transactions.where(date: date.beginning_of_month..date.end_of_month)
      @filter_mode = :month
    else
      # Default to current month
      @current_month = Date.current.beginning_of_month
      @transactions = @transactions.where(date: @current_month..@current_month.end_of_month)
      @filter_mode = :month
    end

    # Account filter
    if params[:account_id].present?
      @transactions = @transactions.where(account_id: params[:account_id])
      @selected_account = Account.find_by(id: params[:account_id])
    end

    # Category filter
    if params[:category_id].present?
      @transactions = @transactions.where(category_id: params[:category_id])
      @selected_category = Category.find_by(id: params[:category_id])
    end

    # For filter dropdowns
    @accounts = Account.order(:name)
    @categories = Category.order(:category_type, :name)

    # Group transactions by date for display
    @transactions_by_date = @transactions.group_by(&:date)

    # Calculate totals
    @total_income = @transactions.income.sum(:amount)
    @total_expenses = @transactions.expense.sum(:amount)
  end

  def show
  end

  def new
    @transaction = Transaction.new(date: Date.current)
  end

  def edit
  end

  def create
    @transaction = Transaction.new(transaction_params)

    if @transaction.save
      redirect_to @transaction, notice: "Transaction was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @transaction.update(transaction_params)
      redirect_to @transaction, notice: "Transaction was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @transaction.destroy!
    redirect_to transactions_path(month: params[:month]), notice: "Transaction was successfully destroyed.", status: :see_other
  end

  private

  def set_transaction
    @transaction = Transaction.find(params.expect(:id))
  end

  def transaction_params
    params.expect(transaction: [ :account_id, :category_id, :amount, :transaction_type, :date, :description ])
  end
end

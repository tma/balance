class TransactionsController < ApplicationController
  before_action :set_transaction, only: %i[ edit update destroy ]

  def index
    @transactions = Transaction.includes(:account, :category).order(date: :desc, created_at: :desc)

    # Search - when searching, ignore date filters and search across all transactions
    if params[:search].present?
      @search_query = params[:search]
      @transactions = @transactions.search(@search_query)
      @filter_mode = :search
    elsif params[:start_date].present? && params[:end_date].present?
      # Date range filtering
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

    # Calculate totals using category type with signed amounts
    # (refunds on expense categories reduce expenses, not inflate income)
    totals = @transactions.joins(:category)
                          .group("categories.category_type")
                          .sum(Transaction.signed_amount_by_category_type_sql)
    @total_income = totals["income"] || 0
    @total_expenses = totals["expense"] || 0
  end

  def new
    @transaction = Transaction.new(date: Date.current)
  end

  def edit
  end

  def create
    @transaction = Transaction.new(transaction_params)

    if @transaction.save
      redirect_to transactions_path, notice: "Transaction was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @transaction.update(transaction_params)
      redirect_to transactions_path, notice: "Transaction was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @transaction.destroy!
    redirect_to transactions_path(filter_params), notice: "Transaction was successfully destroyed.", status: :see_other
  end

  def suggest_category
    description = params[:description].to_s.strip
    transaction_type = params[:transaction_type].to_s.strip

    if description.length < 3
      render json: { category_id: nil }
      return
    end

    txn = {
      description: description,
      transaction_type: transaction_type,
      amount: 0,
      category_id: nil,
      category_name: nil
    }

    service = CategoryMatchingService.new([ txn ])
    service.categorize

    render json: {
      category_id: txn[:category_id],
      category_name: txn[:category_name]
    }
  rescue StandardError => e
    Rails.logger.warn "Category suggestion failed: #{e.message}"
    render json: { category_id: nil }
  end

  private

  def set_transaction
    @transaction = Transaction.find(params.expect(:id))
  end

  def transaction_params
    params.expect(transaction: [ :account_id, :category_id, :amount, :transaction_type, :date, :description ])
  end

  def filter_params
    params.permit(:month, :start_date, :end_date, :account_id, :category_id, :search).to_h.compact_blank
  end
end

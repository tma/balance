class TransactionsController < ApplicationController
  before_action :set_transaction, only: %i[ show edit update destroy ]

  def index
    @transactions = Transaction.includes(:account, :category).order(date: :desc, created_at: :desc)
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
    redirect_to transactions_path, notice: "Transaction was successfully destroyed.", status: :see_other
  end

  private

  def set_transaction
    @transaction = Transaction.find(params.expect(:id))
  end

  def transaction_params
    params.expect(transaction: [ :account_id, :category_id, :amount, :transaction_type, :date, :description ])
  end
end

class AccountsController < ApplicationController
  before_action :set_account, only: %i[ show edit update destroy ]

  def index
    @accounts = Account.includes(:account_type).order(:name)
  end

  def show
    @transactions = @account.transactions.includes(:category).order(date: :desc, created_at: :desc).limit(20)
  end

  def new
    @account = Account.new
  end

  def edit
  end

  def create
    @account = Account.new(account_params)

    if @account.save
      redirect_to @account, notice: "Account was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @account.update(account_params)
      redirect_to @account, notice: "Account was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @account.destroy!
    redirect_to accounts_path, notice: "Account was successfully destroyed.", status: :see_other
  end

  private

  def set_account
    @account = Account.find(params.expect(:id))
  end

  def account_params
    params.expect(account: [ :name, :account_type_id, :balance, :currency ])
  end
end

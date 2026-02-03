class AccountsController < ApplicationController
  before_action :set_account, only: %i[ edit update destroy archive unarchive ]

  def index
    @accounts = Account.includes(:account_type).order(:name)
    # Build a hash of account_id => coverage_analysis for accounts with gaps
    @coverage_gaps = @accounts.active.each_with_object({}) do |account, hash|
      coverage = account.coverage_analysis
      hash[account.id] = coverage if coverage && !coverage[:complete?]
    end
  end

  def new
    @account = Account.new
  end

  def edit
  end

  def create
    @account = Account.new(account_params)

    if @account.save
      redirect_to accounts_path, notice: "Account was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @account.update(account_params)
      redirect_to accounts_path, notice: "Account was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @account.destroy!
    redirect_to accounts_path, notice: "Account was successfully destroyed.", status: :see_other
  end

  def archive
    @account.archive!
    redirect_to accounts_path, notice: "#{@account.name} has been archived.", status: :see_other
  rescue ActiveRecord::RecordInvalid
    redirect_to accounts_path, alert: "Cannot archive #{@account.name}: #{@account.errors.full_messages.join(', ')}", status: :see_other
  end

  def unarchive
    @account.unarchive!
    redirect_to accounts_path, notice: "#{@account.name} has been restored.", status: :see_other
  rescue ActiveRecord::RecordInvalid
    redirect_to accounts_path, alert: "Cannot restore #{@account.name}: #{@account.errors.full_messages.join(', ')}", status: :see_other
  end

  private

  def set_account
    @account = Account.find(params.expect(:id))
  end

  def account_params
    params.expect(account: [ :name, :account_type_id, :balance, :currency, :import_ignore_patterns, :expected_transaction_frequency ])
  end
end

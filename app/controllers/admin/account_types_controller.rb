class Admin::AccountTypesController < ApplicationController
  before_action :set_account_type, only: %i[show edit update destroy]

  def index
    @account_types = AccountType.all.order(:name)
  end

  def show
  end

  def new
    @account_type = AccountType.new
  end

  def edit
  end

  def create
    @account_type = AccountType.new(account_type_params)

    if @account_type.save
      redirect_to admin_account_type_path(@account_type), notice: "Account type was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @account_type.update(account_type_params)
      redirect_to admin_account_type_path(@account_type), notice: "Account type was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @account_type.destroy!
    redirect_to admin_account_types_path, notice: "Account type was successfully destroyed.", status: :see_other
  end

  private

  def set_account_type
    @account_type = AccountType.find(params.expect(:id))
  end

  def account_type_params
    params.expect(account_type: [:name])
  end
end

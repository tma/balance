class Admin::AccountTypesController < ApplicationController
  before_action :set_account_type, only: %i[ show edit update destroy ]

  # GET /admin/account_types or /admin/account_types.json
  def index
    @account_types = AccountType.all.order(:name)
  end

  # GET /admin/account_types/1 or /admin/account_types/1.json
  def show
  end

  # GET /admin/account_types/new
  def new
    @account_type = AccountType.new
  end

  # GET /admin/account_types/1/edit
  def edit
  end

  # POST /admin/account_types or /admin/account_types.json
  def create
    @account_type = AccountType.new(account_type_params)

    respond_to do |format|
      if @account_type.save
        format.html { redirect_to admin_account_type_path(@account_type), notice: "Account type was successfully created." }
        format.json { render :show, status: :created, location: admin_account_type_path(@account_type) }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @account_type.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /admin/account_types/1 or /admin/account_types/1.json
  def update
    respond_to do |format|
      if @account_type.update(account_type_params)
        format.html { redirect_to admin_account_type_path(@account_type), notice: "Account type was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: admin_account_type_path(@account_type) }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @account_type.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /admin/account_types/1 or /admin/account_types/1.json
  def destroy
    @account_type.destroy!

    respond_to do |format|
      format.html { redirect_to admin_account_types_path, notice: "Account type was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private

  def set_account_type
    @account_type = AccountType.find(params.expect(:id))
  end

  def account_type_params
    params.expect(account_type: [ :name ])
  end
end

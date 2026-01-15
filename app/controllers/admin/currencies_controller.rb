class Admin::CurrenciesController < ApplicationController
  before_action :set_currency, only: %i[ show edit update destroy ]

  # GET /admin/currencies or /admin/currencies.json
  def index
    @currencies = Currency.all.order(:code)
  end

  # GET /admin/currencies/1 or /admin/currencies/1.json
  def show
  end

  # GET /admin/currencies/new
  def new
    @currency = Currency.new
  end

  # GET /admin/currencies/1/edit
  def edit
  end

  # POST /admin/currencies or /admin/currencies.json
  def create
    @currency = Currency.new(currency_params)

    respond_to do |format|
      if @currency.save
        format.html { redirect_to admin_currency_path(@currency), notice: "Currency was successfully created." }
        format.json { render :show, status: :created, location: admin_currency_path(@currency) }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @currency.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /admin/currencies/1 or /admin/currencies/1.json
  def update
    respond_to do |format|
      if @currency.update(currency_params)
        format.html { redirect_to admin_currency_path(@currency), notice: "Currency was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: admin_currency_path(@currency) }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @currency.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /admin/currencies/1 or /admin/currencies/1.json
  def destroy
    @currency.destroy!

    respond_to do |format|
      format.html { redirect_to admin_currencies_path, notice: "Currency was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private

  def set_currency
    @currency = Currency.find(params.expect(:id))
  end

  def currency_params
    params.expect(currency: [ :code ])
  end
end

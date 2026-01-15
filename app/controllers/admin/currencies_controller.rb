class Admin::CurrenciesController < ApplicationController
  before_action :set_currency, only: %i[ show edit update destroy ]

  def index
    @currencies = Currency.all.order(:code)
  end

  def show
  end

  def new
    @currency = Currency.new
  end

  def edit
  end

  def create
    @currency = Currency.new(currency_params)

    if @currency.save
      redirect_to admin_currency_path(@currency), notice: "Currency was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @currency.update(currency_params)
      redirect_to admin_currency_path(@currency), notice: "Currency was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @currency.destroy!
    redirect_to admin_currencies_path, notice: "Currency was successfully destroyed.", status: :see_other
  end

  private

  def set_currency
    @currency = Currency.find(params.expect(:id))
  end

  def currency_params
    params.expect(currency: [ :code ])
  end
end

class AssetsController < ApplicationController
  before_action :set_asset, only: %i[show edit update destroy]

  def index
    @assets = Asset.includes(:asset_type).assets_only.order(:name)
    @liabilities = Asset.includes(:asset_type).liabilities_only.order(:name)
  end

  def show
    @valuations = @asset.asset_valuations.limit(20)
  end

  def new
    @asset = Asset.new
  end

  def edit
  end

  def create
    @asset = Asset.new(asset_params)

    if @asset.save
      redirect_to @asset, notice: "Asset was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @asset.update(asset_params)
      redirect_to @asset, notice: "Asset was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @asset.destroy!
    redirect_to assets_path, notice: "Asset was successfully destroyed.", status: :see_other
  end

  private

  def set_asset
    @asset = Asset.find(params.expect(:id))
  end

  def asset_params
    params.expect(asset: [:name, :asset_type_id, :value, :currency, :notes])
  end
end

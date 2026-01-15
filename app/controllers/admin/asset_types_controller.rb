class Admin::AssetTypesController < ApplicationController
  before_action :set_asset_type, only: %i[show edit update destroy]

  def index
    @asset_types = AssetType.all.order(:is_liability, :name)
  end

  def show
  end

  def new
    @asset_type = AssetType.new
  end

  def edit
  end

  def create
    @asset_type = AssetType.new(asset_type_params)

    if @asset_type.save
      redirect_to admin_asset_type_path(@asset_type), notice: "Asset type was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @asset_type.update(asset_type_params)
      redirect_to admin_asset_type_path(@asset_type), notice: "Asset type was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @asset_type.destroy!
    redirect_to admin_asset_types_path, notice: "Asset type was successfully destroyed.", status: :see_other
  end

  private

  def set_asset_type
    @asset_type = AssetType.find(params.expect(:id))
  end

  def asset_type_params
    params.expect(asset_type: [:name, :is_liability])
  end
end

class AssetsController < ApplicationController
  before_action :set_asset, only: %i[ show edit update destroy ]

  def index
    @asset_groups = AssetGroup.includes(assets: :asset_type)
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
    @asset.position = @asset.asset_group.assets.maximum(:position).to_i + 1 if @asset.asset_group

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

  def sort
    params[:positions].each do |id, position|
      Asset.where(id: id).update_all(position: position)
    end
    head :ok
  end

  private

  def set_asset
    @asset = Asset.find(params.expect(:id))
  end

  def asset_params
    params.expect(asset: [ :name, :asset_type_id, :asset_group_id, :value, :currency, :notes ])
  end
end

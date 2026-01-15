class AssetGroupsController < ApplicationController
  before_action :set_asset_group, only: %i[ show edit update destroy ]

  def index
    @asset_groups = AssetGroup.includes(assets: :asset_type).order(:name)
  end

  def show
    @assets = @asset_group.assets.includes(:asset_type).assets_only.order(:name)
    @liabilities = @asset_group.assets.includes(:asset_type).liabilities_only.order(:name)
  end

  def new
    @asset_group = AssetGroup.new
  end

  def edit
  end

  def create
    @asset_group = AssetGroup.new(asset_group_params)

    if @asset_group.save
      redirect_to @asset_group, notice: "Asset group was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @asset_group.update(asset_group_params)
      redirect_to @asset_group, notice: "Asset group was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @asset_group.destroy!
    redirect_to asset_groups_path, notice: "Asset group was successfully destroyed.", status: :see_other
  end

  private

  def set_asset_group
    @asset_group = AssetGroup.find(params.expect(:id))
  end

  def asset_group_params
    params.expect(asset_group: [ :name, :description ])
  end
end

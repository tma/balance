class Admin::AssetTypesController < ApplicationController
  before_action :set_asset_type, only: %i[ show edit update destroy ]

  # GET /admin/asset_types or /admin/asset_types.json
  def index
    @asset_types = AssetType.all.order(:is_liability, :name)
  end

  # GET /admin/asset_types/1 or /admin/asset_types/1.json
  def show
  end

  # GET /admin/asset_types/new
  def new
    @asset_type = AssetType.new
  end

  # GET /admin/asset_types/1/edit
  def edit
  end

  # POST /admin/asset_types or /admin/asset_types.json
  def create
    @asset_type = AssetType.new(asset_type_params)

    respond_to do |format|
      if @asset_type.save
        format.html { redirect_to admin_asset_type_path(@asset_type), notice: "Asset type was successfully created." }
        format.json { render :show, status: :created, location: admin_asset_type_path(@asset_type) }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @asset_type.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /admin/asset_types/1 or /admin/asset_types/1.json
  def update
    respond_to do |format|
      if @asset_type.update(asset_type_params)
        format.html { redirect_to admin_asset_type_path(@asset_type), notice: "Asset type was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: admin_asset_type_path(@asset_type) }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @asset_type.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /admin/asset_types/1 or /admin/asset_types/1.json
  def destroy
    @asset_type.destroy!

    respond_to do |format|
      format.html { redirect_to admin_asset_types_path, notice: "Asset type was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private

  def set_asset_type
    @asset_type = AssetType.find(params.expect(:id))
  end

  def asset_type_params
    params.expect(asset_type: [ :name, :is_liability ])
  end
end

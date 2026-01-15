class AssetsController < ApplicationController
  before_action :set_asset, only: %i[ show edit update destroy ]

  # GET /assets or /assets.json
  def index
    @assets = Asset.includes(:asset_type).assets_only.order(:name)
    @liabilities = Asset.includes(:asset_type).liabilities_only.order(:name)
  end

  # GET /assets/1 or /assets/1.json
  def show
    @valuations = @asset.asset_valuations.limit(20)
  end

  # GET /assets/new
  def new
    @asset = Asset.new
  end

  # GET /assets/1/edit
  def edit
  end

  # POST /assets or /assets.json
  def create
    @asset = Asset.new(asset_params)

    respond_to do |format|
      if @asset.save
        format.html { redirect_to @asset, notice: "Asset was successfully created." }
        format.json { render :show, status: :created, location: @asset }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @asset.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /assets/1 or /assets/1.json
  def update
    respond_to do |format|
      if @asset.update(asset_params)
        format.html { redirect_to @asset, notice: "Asset was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @asset }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @asset.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /assets/1 or /assets/1.json
  def destroy
    @asset.destroy!

    respond_to do |format|
      format.html { redirect_to assets_path, notice: "Asset was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private

  def set_asset
    @asset = Asset.find(params.expect(:id))
  end

  def asset_params
    params.expect(asset: [ :name, :asset_type_id, :value, :currency, :notes ])
  end
end

class AssetValuationsController < ApplicationController
  def edit
    @asset_groups = AssetGroup.includes(assets: :asset_type).order(:name)
    @date = Date.current
  end

  def update
    @date = params[:date].present? ? Date.parse(params[:date]) : Date.current
    updated_count = 0
    errors = []

    ActiveRecord::Base.transaction do
      params[:assets]&.each do |asset_id, value|
        next if value.blank?

        asset = Asset.find(asset_id)
        new_value = BigDecimal(value)

        # Only update if value changed
        if asset.value != new_value
          asset.update!(value: new_value)
          updated_count += 1
        end
      end
    end

    if errors.empty?
      redirect_to update_valuations_path, notice: "Updated #{updated_count} asset #{'valuation'.pluralize(updated_count)}."
    else
      redirect_to update_valuations_path, alert: "Some updates failed: #{errors.join(', ')}"
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_to update_valuations_path, alert: "Update failed: #{e.message}"
  end

  def destroy
    @asset = Asset.find(params[:asset_id])
    @valuation = @asset.asset_valuations.find(params[:id])
    @valuation.destroy!
    redirect_to @asset, notice: "Valuation deleted.", status: :see_other
  end
end

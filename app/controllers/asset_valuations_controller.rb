class AssetValuationsController < ApplicationController
  # Bulk update form for all assets - multi-month view
  def bulk_edit
    @asset_groups = AssetGroup.includes(assets: [ :asset_type, :asset_valuations ]).order(:name)
    
    # Parse month parameter or default to current month
    if params[:month].present?
      @end_month = Date.parse("#{params[:month]}-01").end_of_month
    else
      @end_month = Date.current.end_of_month
    end
    @current_month = @end_month.strftime("%Y-%m")
    
    @months = build_months_range(@end_month)
    @valuations_by_asset_and_month = build_valuations_lookup
    @group_totals_by_month = build_group_totals_by_month
    @totals_by_month = build_totals_by_month
  end

  # Process bulk updates for multiple months
  def bulk_update
    updated_count = 0

    ActiveRecord::Base.transaction do
      params[:valuations]&.each do |asset_id, months_data|
        asset = Asset.find(asset_id)

        months_data.each do |date_str, value|
          next if value.blank?

          date = Date.parse(date_str)
          new_value = BigDecimal(value)

          # Find existing valuation or build new one
          valuation = asset.asset_valuations.find_or_initialize_by(date: date)

          # Only save if value changed or new record
          if valuation.new_record? || valuation.value != new_value
            valuation.value = new_value
            valuation.save!
            updated_count += 1

            # Update asset's current value if this is the most recent valuation
            if date == asset.asset_valuations.maximum(:date) || asset.asset_valuations.count == 1
              asset.update_column(:value, new_value)
            end
          end
        end
      end
    end

    redirect_to update_valuations_path, notice: "Saved #{updated_count} #{'valuation'.pluralize(updated_count)}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to update_valuations_path, alert: "Update failed: #{e.message}"
  end

  private

  def build_months_range(end_month)
    # Show 12 months ending at end_month
    (0..11).map { |i| (end_month - i.months).end_of_month }.reverse
  end

  def build_valuations_lookup
    # Build a hash: { asset_id => { date => value } }
    lookup = Hash.new { |h, k| h[k] = {} }

    AssetValuation.find_each do |v|
      lookup[v.asset_id][v.date] = v.value
    end

    lookup
  end

  def build_group_totals_by_month
    # Build a hash: { group_id => { date => net_value } }
    totals = Hash.new { |h, k| h[k] = {} }

    @asset_groups.each do |group|
      @months.each do |month|
        net = 0
        group.assets.each do |asset|
          value = @valuations_by_asset_and_month[asset.id][month]
          next unless value

          # Convert to default currency
          valuation = asset.asset_valuations.find { |v| v.date == month }
          value_in_default = valuation&.value_in_default_currency || value

          if asset.asset_type.is_liability
            net -= value_in_default
          else
            net += value_in_default
          end
        end
        totals[group.id][month] = net
      end
    end

    totals
  end

  def build_totals_by_month
    # Build a hash: { date => total_net_value }
    totals = {}

    @months.each do |month|
      totals[month] = @group_totals_by_month.values.sum { |group_months| group_months[month] || 0 }
    end

    totals
  end

  # Edit individual valuation date
  def edit
    @asset = Asset.find(params[:asset_id])
    @valuation = @asset.asset_valuations.find(params[:id])
  end

  # Update individual valuation date
  def update
    @asset = Asset.find(params[:asset_id])
    @valuation = @asset.asset_valuations.find(params[:id])

    if @valuation.update(valuation_params)
      redirect_to @asset, notice: "Valuation updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @asset = Asset.find(params[:asset_id])
    @valuation = @asset.asset_valuations.find(params[:id])
    @valuation.destroy!
    redirect_to @asset, notice: "Valuation deleted.", status: :see_other
  end

  private

  def valuation_params
    params.require(:asset_valuation).permit(:date, :value)
  end
end

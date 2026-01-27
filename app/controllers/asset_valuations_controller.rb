class AssetValuationsController < ApplicationController
  # Bulk update form for all assets - multi-month view
  def bulk_edit
    @asset_groups = AssetGroup.includes(assets: [ :asset_type, :asset_valuations, :broker_positions ]).order(:name)

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

    # Check if there are any broker connections
    @has_broker_connections = BrokerConnection.exists?
    @broker_asset_ids = BrokerPosition.where.not(asset_id: nil).pluck(:asset_id).uniq.to_set
  end

  # Apply cached broker position values to assets (no API call)
  # Positions are synced automatically at 11:30pm daily
  def apply_broker_values
    assets = Asset.with_broker.includes(:broker_positions)
    updated_count = 0

    assets.each do |asset|
      asset.sync_from_broker_positions!
      updated_count += 1
    rescue StandardError => e
      Rails.logger.error "[apply_broker_values] Failed to update #{asset.name}: #{e.message}"
    end

    redirect_to update_valuations_path, notice: "Applied broker values to #{updated_count} #{'asset'.pluralize(updated_count)}."
  end

  # Process bulk updates for multiple months
  def bulk_update
    updated_count = 0

    ActiveRecord::Base.transaction do
      params[:valuations]&.each do |asset_id, months_data|
        asset = Asset.find(asset_id)

        months_data.each do |date_str, value|
          # Skip formula keys (they're handled with their corresponding value)
          next if date_str.end_with?("_formula")
          next if value.blank?

          date = Date.parse(date_str)

          # Check for formula (in separate param)
          formula_key = "#{date_str}_formula"
          formula = months_data[formula_key]

          # Strip non-numeric characters (currency codes, spaces, thousand separators)
          sanitized_value = value.to_s.gsub(/[^\d.]/, "")
          next if sanitized_value.blank?

          new_value = BigDecimal(sanitized_value)

          # Find existing valuation or build new one
          valuation = asset.asset_valuations.find_or_initialize_by(date: date)

          # Track if anything changed
          value_changed = valuation.new_record? || valuation.value != new_value
          formula_changed = valuation.formula != formula

          # Only save if value or formula changed
          if value_changed || formula_changed
            valuation.value = new_value
            valuation.formula = formula.presence  # nil if blank/plain number
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

  def build_months_range(end_month)
    # Show 12 months ending at end_month
    (0..11).map { |i| (end_month - i.months).end_of_month }.reverse
  end

  def build_valuations_lookup
    # Build a hash: { asset_id => { date => value } }
    lookup = Hash.new { |h, k| h[k] = {} }
    formulas = Hash.new { |h, k| h[k] = {} }

    AssetValuation.all.each do |v|
      lookup[v.asset_id][v.date] = v.value
      formulas[v.asset_id][v.date] = v.formula if v.formula.present?
    end

    @formulas_by_asset_and_month = formulas
    lookup
  end

  def build_group_totals_by_month
    # Build a hash: { group_id => { date => net_value } }
    # Includes all assets (active and archived)
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

  def valuation_params
    params.require(:asset_valuation).permit(:date, :value)
  end
end

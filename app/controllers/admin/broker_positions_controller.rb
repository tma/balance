class Admin::BrokerPositionsController < ApplicationController
  before_action :set_connection
  before_action :set_position, only: %i[show edit update]

  def index
    @positions = @connection.broker_positions.includes(:asset).order(:symbol)
    @assets = Asset.includes(:asset_group, :asset_type).order(:name)
  end

  def show
    @valuations = @position.position_valuations.order(date: :desc).limit(90)
  end

  def edit
    @assets = Asset.includes(:asset_group, :asset_type).order(:name)
  end

  def update
    if @position.update(position_params)
      # Sync value to asset if now mapped
      @position.sync_to_asset! if @position.mapped?

      redirect_to admin_broker_connection_path(@connection),
        notice: "Position mapping updated.", status: :see_other
    else
      @assets = Asset.includes(:asset_group, :asset_type).order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  # Bulk update mappings
  def bulk_update
    updated_count = 0

    ActiveRecord::Base.transaction do
      params[:positions]&.each do |position_id, asset_id|
        position = @connection.broker_positions.find(position_id)
        new_asset_id = asset_id.presence

        if position.asset_id != new_asset_id&.to_i
          position.update!(asset_id: new_asset_id)
          position.sync_to_asset! if position.mapped?
          updated_count += 1
        end
      end
    end

    redirect_to admin_broker_connection_path(@connection),
      notice: "Updated #{updated_count} #{'mapping'.pluralize(updated_count)}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_broker_connection_path(@connection),
      alert: "Update failed: #{e.message}"
  end

  private

  def set_connection
    @connection = BrokerConnection.find(params.expect(:broker_connection_id))
  end

  def set_position
    @position = @connection.broker_positions.find(params.expect(:id))
  end

  def position_params
    params.expect(broker_position: [ :asset_id ])
  end
end

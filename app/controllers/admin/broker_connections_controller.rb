class Admin::BrokerConnectionsController < ApplicationController
  before_action :set_connection, only: %i[show edit update destroy sync]

  def index
    @connections = BrokerConnection.all.order(:name)
  end

  def show
    @positions = @connection.broker_positions.includes(:asset, :position_valuations).order(:symbol)
    @asset_groups = AssetGroup.includes(assets: :asset_type).order(:position, :name)
    @default_currency = Currency.default_code
  end

  def new
    @connection = BrokerConnection.new(broker_type: :ibkr)
  end

  def edit
  end

  def create
    @connection = BrokerConnection.new(connection_params)

    if @connection.save
      redirect_to admin_broker_connection_path(@connection), notice: "Connection was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @connection.update(connection_params)
      redirect_to admin_broker_connection_path(@connection), notice: "Connection was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @connection.destroy!
    redirect_to admin_broker_connections_path, notice: "Connection was successfully deleted.", status: :see_other
  end

  def sync
    result = BrokerSyncBackfillService.sync_missing_dates!(@connection)
    message = if result[:dates].empty?
      "Sync already up to date."
    else
      "Sync completed for #{result[:synced]} day(s)."
    end
    redirect_to admin_broker_connection_path(@connection), notice: message
  rescue => e
    redirect_to admin_broker_connection_path(@connection), alert: "Sync failed: #{e.message}"
  end

  def test_connection
    # Build a temporary connection object (not saved) to test credentials
    @connection = BrokerConnection.new(connection_params)

    # Only validate presence of required fields, not uniqueness
    errors = []
    errors << "Name can't be blank" if @connection.name.blank?
    if @connection.ibkr?
      errors << "Flex Token can't be blank" if @connection.flex_token.blank?
      errors << "Flex Query ID can't be blank" if @connection.flex_query_id.blank?
    end

    if errors.any?
      render json: { success: false, error: errors.join(", ") }
      return
    end

    service = BrokerSyncService.for(@connection)
    result = service.test_connection

    render json: result
  end

  private

  def set_connection
    @connection = BrokerConnection.find(params.expect(:id))
  end

  def connection_params
    params.expect(broker_connection: [ :name, :flex_token, :flex_query_id, :broker_type ])
  end
end

class Admin::PositionValuationsController < ApplicationController
  before_action :set_connection
  before_action :set_position
  before_action :set_valuation, only: %i[update destroy]

  def update
    if @valuation.update(valuation_params)
      redirect_to admin_broker_connection_position_path(@connection, @position),
        notice: "Valuation updated.", status: :see_other
    else
      redirect_to admin_broker_connection_position_path(@connection, @position),
        alert: "Update failed: #{@valuation.errors.full_messages.join(', ')}", status: :see_other
    end
  end

  def destroy
    @valuation.destroy
    redirect_to admin_broker_connection_position_path(@connection, @position),
      notice: "Valuation deleted.", status: :see_other
  end

  private

  def set_connection
    @connection = BrokerConnection.find(params.expect(:broker_connection_id))
  end

  def set_position
    @position = @connection.broker_positions.find(params.expect(:position_id))
  end

  def set_valuation
    @valuation = @position.position_valuations.find(params.expect(:id))
  end

  def valuation_params
    params.expect(position_valuation: [ :quantity, :value ])
  end
end

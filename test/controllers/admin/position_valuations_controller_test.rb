require "test_helper"

class Admin::PositionValuationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @connection = broker_connections(:one)
    @position = broker_positions(:aapl_position)
    @valuation = position_valuations(:aapl_jan_18)
  end

  test "should update valuation" do
    patch admin_broker_connection_position_valuation_url(@connection, @position, @valuation), params: {
      position_valuation: { quantity: 150, value: 25000 }
    }
    assert_redirected_to admin_broker_connection_position_path(@connection, @position)

    @valuation.reload
    assert_equal 150, @valuation.quantity
    assert_equal 25000, @valuation.value
  end

  test "should destroy valuation" do
    assert_difference("PositionValuation.count", -1) do
      delete admin_broker_connection_position_valuation_url(@connection, @position, @valuation)
    end
    assert_redirected_to admin_broker_connection_position_path(@connection, @position)
  end
end

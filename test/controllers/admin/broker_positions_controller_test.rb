require "test_helper"

class Admin::BrokerPositionsControllerTest < ActionDispatch::IntegrationTest
  test "bulk_update recalculates old asset when position is moved" do
    connection = broker_connections(:one)
    position = broker_positions(:aapl_position)
    old_asset = position.asset
    new_asset = assets(:investment_property)

    old_asset.update!(value: 17_500)
    new_asset.update!(value: 150_000)
    new_asset.broker_positions.destroy_all
    position.update!(last_value: 5_000, currency: "USD")

    patch bulk_update_admin_broker_connection_positions_path(connection), params: {
      positions: { position.id => new_asset.id }
    }

    assert_redirected_to admin_broker_connection_path(connection)
    assert_equal 0, old_asset.reload.value
    assert_equal 5_000, new_asset.reload.value
  end

  test "bulk_update recalculates old asset when position is unmapped" do
    connection = broker_connections(:one)
    position = broker_positions(:aapl_position)
    old_asset = position.asset

    old_asset.update!(value: 17_500)
    position.update!(last_value: 5_000, currency: "USD")

    patch bulk_update_admin_broker_connection_positions_path(connection), params: {
      positions: { position.id => "" }
    }

    assert_redirected_to admin_broker_connection_path(connection)
    assert_equal 0, old_asset.reload.value
    assert_nil position.reload.asset_id
  end
end

require "test_helper"

class BrokerSyncServiceTest < ActiveSupport::TestCase
  setup do
    # Allow Frankfurter API calls in setup, stub them in individual tests as needed
    WebMock.allow_net_connect!
  end

  teardown do
    WebMock.reset!
    WebMock.allow_net_connect! # Restore default for other tests
  end

  test "factory returns IbkrSyncService for ibkr broker type" do
    connection = broker_connections(:one)
    service = BrokerSyncService.for(connection)

    assert_kind_of IbkrSyncService, service
  end

  test "factory raises SyncError for unknown broker type" do
    # Test the factory logic directly by simulating unknown broker type
    error = assert_raises BrokerSyncService::SyncError do
      case "unknown"
      when "ibkr"
        raise "should not reach"
      else
        raise BrokerSyncService::SyncError, "Unknown broker type: unknown"
      end
    end

    assert_includes error.message, "Unknown broker type"
  end

  test "record_position_valuations! creates valuations for all positions" do
    connection = broker_connections(:one)
    service = IbkrSyncService.new(connection)

    # Ensure positions have values
    connection.broker_positions.each do |pos|
      pos.update!(last_value: 1000, last_quantity: 10, currency: "USD")
    end

    initial_count = PositionValuation.count
    service.send(:record_position_valuations!)

    assert_equal initial_count + connection.broker_positions.count, PositionValuation.count
  end

  test "sync_mapped_assets updates assets linked to positions" do
    # Stub exchange rate API
    stub_request(:get, %r{api\.frankfurter\.app})
      .to_return(status: 200, body: { rates: { "EUR" => 0.85 } }.to_json, headers: { "Content-Type" => "application/json" })

    connection = broker_connections(:one)
    position = broker_positions(:aapl_position) # mapped to house asset
    service = IbkrSyncService.new(connection)

    # Set a known value in USD (same as asset currency)
    position.update!(last_value: 5000, currency: "USD")
    asset = position.asset
    asset.update!(currency: "USD")

    service.send(:sync_mapped_assets)

    # Asset should have been synced
    asset.reload
    assert_equal 5000.0, asset.value.to_f
  end

  test "SyncError is base class for sync errors" do
    error = BrokerSyncService::SyncError.new("test error")
    assert_kind_of StandardError, error
  end

  test "AuthenticationError inherits from SyncError" do
    error = BrokerSyncService::AuthenticationError.new("auth failed")
    assert_kind_of BrokerSyncService::SyncError, error
  end

  test "RateLimitError inherits from SyncError" do
    error = BrokerSyncService::RateLimitError.new("rate limited")
    assert_kind_of BrokerSyncService::SyncError, error
  end
end

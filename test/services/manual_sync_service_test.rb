require "test_helper"

class ManualSyncServiceTest < ActiveSupport::TestCase
  setup do
    @connection = broker_connections(:manual_crypto)
    @service = ManualSyncService.new(@connection)

    # Stub all HTTP requests by default
    WebMock.disable_net_connect!
  end

  teardown do
    WebMock.reset!
    WebMock.allow_net_connect! # Restore default for other tests
  end

  # ============================================================
  # CoinGecko API Response Fixtures
  # ============================================================

  def coingecko_success_response
    {
      "bitcoin" => { "usd" => 83784.0 },
      "ethereum" => { "usd" => 2787.27 }
    }.to_json
  end

  def coingecko_single_response
    {
      "bitcoin" => { "usd" => 100000.0 }
    }.to_json
  end

  # ============================================================
  # Test Connection Tests
  # ============================================================

  test "test_connection returns success when CoinGecko API is reachable" do
    stub_request(:get, %r{api\.coingecko\.com/api/v3/simple/price})
      .with(query: hash_including("ids" => "bitcoin", "vs_currencies" => "usd"))
      .to_return(status: 200, body: coingecko_single_response, headers: { "Content-Type" => "application/json" })

    result = @service.test_connection

    assert result[:success]
    assert_equal "CoinGecko API reachable", result[:message]
    assert_equal 100000.0, result[:btc_price]
  end

  test "test_connection returns failure when CoinGecko API returns error" do
    stub_request(:get, %r{api\.coingecko\.com})
      .to_return(status: 500, body: "Internal Server Error")

    result = @service.test_connection

    assert_not result[:success]
    assert_includes result[:error], "CoinGecko API error"
  end

  test "test_connection returns failure when network error occurs" do
    stub_request(:get, %r{api\.coingecko\.com})
      .to_timeout

    result = @service.test_connection

    assert_not result[:success]
    assert_includes result[:error], "timeout"
  end

  # ============================================================
  # Sync Tests
  # ============================================================

  test "perform_sync! updates crypto position values from CoinGecko" do
    stub_request(:get, %r{api\.coingecko\.com/api/v3/simple/price})
      .to_return(status: 200, body: coingecko_success_response, headers: { "Content-Type" => "application/json" })

    btc_position = broker_positions(:btc_position)
    btc_position.update!(last_quantity: 0.15, last_value: 0)

    result = @service.perform_sync!

    btc_position.reload
    # 0.15 * 83784 = 12567.60
    assert_equal 12567.60, btc_position.last_value.to_f
    assert btc_position.last_synced_at > 1.minute.ago
    assert_equal 2, result[:positions].count
    assert result[:errors].empty?
  end

  test "perform_sync! creates position valuations" do
    stub_request(:get, %r{api\.coingecko\.com/api/v3/simple/price})
      .to_return(status: 200, body: coingecko_success_response, headers: { "Content-Type" => "application/json" })

    initial_count = PositionValuation.count

    @service.perform_sync!

    assert_equal initial_count + 2, PositionValuation.count
  end

  test "perform_sync! updates connection last_synced_at on success" do
    stub_request(:get, %r{api\.coingecko\.com/api/v3/simple/price})
      .to_return(status: 200, body: coingecko_success_response, headers: { "Content-Type" => "application/json" })

    @connection.update!(last_synced_at: 1.day.ago, last_sync_error: "old error")

    @service.perform_sync!

    @connection.reload
    assert @connection.last_synced_at > 1.minute.ago
    assert_nil @connection.last_sync_error
  end

  test "perform_sync! returns empty result when no crypto positions exist" do
    # Remove all positions from the manual connection
    @connection.broker_positions.destroy_all

    result = @service.perform_sync!

    assert_equal [], result[:positions]
    assert_equal 0, result[:updated_count]
  end

  test "perform_sync! skips non-crypto positions" do
    stub_request(:get, %r{api\.coingecko\.com/api/v3/simple/price})
      .to_return(status: 200, body: coingecko_success_response, headers: { "Content-Type" => "application/json" })

    # Create a non-crypto position
    @connection.broker_positions.create!(
      symbol: "AAPL",
      description: "Apple Inc",
      currency: "USD",
      last_quantity: 10
    )

    result = @service.perform_sync!

    # Should only sync crypto positions (BTC, ETH)
    assert_equal 2, result[:positions].count
    symbols = result[:positions].map(&:symbol)
    assert_not_includes symbols, "AAPL"
  end

  test "perform_sync! skips positions with missing price from CoinGecko" do
    # Only return BTC price, not ETH
    stub_request(:get, %r{api\.coingecko\.com/api/v3/simple/price})
      .to_return(status: 200, body: { "bitcoin" => { "usd" => 83784.0 } }.to_json, headers: { "Content-Type" => "application/json" })

    result = @service.perform_sync!

    # Only BTC should be updated
    assert_equal 1, result[:positions].count
    assert_equal "BTC", result[:positions].first.symbol
  end

  # ============================================================
  # Error Handling Tests
  # ============================================================

  test "perform_sync! raises SyncError on CoinGecko API error" do
    stub_request(:get, %r{api\.coingecko\.com})
      .to_return(status: 500, body: "Internal Server Error")

    error = assert_raises BrokerSyncService::SyncError do
      @service.perform_sync!
    end

    assert_includes error.message, "CoinGecko API error"

    @connection.reload
    assert_includes @connection.last_sync_error, "CoinGecko API error"
  end

  test "perform_sync! raises SyncError on invalid JSON response" do
    stub_request(:get, %r{api\.coingecko\.com})
      .to_return(status: 200, body: "not json", headers: { "Content-Type" => "application/json" })

    error = assert_raises BrokerSyncService::SyncError do
      @service.perform_sync!
    end

    assert_includes error.message, "Invalid response"
  end

  test "perform_sync! raises SyncError on network timeout" do
    stub_request(:get, %r{api\.coingecko\.com})
      .to_timeout

    error = assert_raises BrokerSyncService::SyncError do
      @service.perform_sync!
    end

    assert_includes error.message, "timeout"
  end

  # ============================================================
  # CoinGecko Symbol Mapping Tests
  # ============================================================

  test "BrokerPosition#coingecko_id maps known crypto symbols" do
    position = BrokerPosition.new(symbol: "BTC")
    assert_equal "bitcoin", position.coingecko_id

    position = BrokerPosition.new(symbol: "ETH")
    assert_equal "ethereum", position.coingecko_id

    position = BrokerPosition.new(symbol: "SOL")
    assert_equal "solana", position.coingecko_id
  end

  test "BrokerPosition#coingecko_id returns nil for unknown symbols" do
    position = BrokerPosition.new(symbol: "AAPL")
    assert_nil position.coingecko_id

    position = BrokerPosition.new(symbol: "UNKNOWN")
    assert_nil position.coingecko_id
  end

  test "BrokerPosition#crypto_position? returns true for crypto symbols" do
    position = BrokerPosition.new(symbol: "BTC")
    assert position.crypto_position?
  end

  test "BrokerPosition#crypto_position? returns false for non-crypto symbols" do
    position = BrokerPosition.new(symbol: "AAPL")
    assert_not position.crypto_position?
  end
end

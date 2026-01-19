require "test_helper"

class IbkrSyncServiceTest < ActiveSupport::TestCase
  # Testable subclass that skips sleep
  class TestableIbkrSyncService < IbkrSyncService
    private

    def wait(_seconds)
      # No-op in tests
    end
  end

  setup do
    # Create a fresh connection with known credentials for each test
    @connection = BrokerConnection.create!(
      broker_type: :ibkr,
      account_id: "U9999999",
      name: "Test IBKR Account",
      flex_token: "test_token_abc123",
      flex_query_id: "999999"
    )
    @service = TestableIbkrSyncService.new(@connection)

    # Stub all HTTP requests by default
    WebMock.disable_net_connect!

    # Stub Frankfurter API for currency conversion
    stub_request(:get, %r{api\.frankfurter\.app})
      .to_return(status: 200, body: { rates: { "EUR" => 0.85, "USD" => 1.0 } }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  teardown do
    WebMock.reset!
    WebMock.allow_net_connect! # Restore default for other tests
    @connection.destroy if @connection.persisted?
  end

  # ============================================================
  # XML Response Fixtures
  # ============================================================

  def success_send_response
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <FlexStatementResponse timestamp="20260119;12345">
        <Status>Success</Status>
        <ReferenceCode>REF123456</ReferenceCode>
        <Url>https://example.com/report</Url>
      </FlexStatementResponse>
    XML
  end

  def success_statement_response
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <FlexQueryResponse queryName="Balance Positions" type="AF">
        <FlexStatements count="1">
          <FlexStatement accountId="U9999999" fromDate="20260101" toDate="20260119">
            <OpenPositions>
              <OpenPosition symbol="VTI" description="Vanguard Total Stock Market ETF"
                position="100.0" positionValue="25000.00" currency="USD" levelOfDetail="SUMMARY"/>
              <OpenPosition symbol="AAPL" description="Apple Inc"
                position="50.0" positionValue="8750.00" currency="USD" levelOfDetail="SUMMARY"/>
              <OpenPosition symbol="AAPL" description="Apple Inc - Lot 1"
                position="30.0" positionValue="5250.00" currency="USD" levelOfDetail="LOT"/>
              <OpenPosition symbol="AAPL" description="Apple Inc - Lot 2"
                position="20.0" positionValue="3500.00" currency="USD" levelOfDetail="LOT"/>
            </OpenPositions>
          </FlexStatement>
        </FlexStatements>
      </FlexQueryResponse>
    XML
  end

  def error_auth_response
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <FlexStatementResponse timestamp="20260119;12345">
        <Status>Fail</Status>
        <ErrorCode>1012</ErrorCode>
        <ErrorMessage>Token has expired or is invalid.</ErrorMessage>
      </FlexStatementResponse>
    XML
  end

  def error_rate_limit_response
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <FlexStatementResponse timestamp="20260119;12345">
        <Status>Fail</Status>
        <ErrorCode>1018</ErrorCode>
        <ErrorMessage>Too many requests. Please try again later.</ErrorMessage>
      </FlexStatementResponse>
    XML
  end

  def error_generation_in_progress_response
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <FlexStatementResponse timestamp="20260119;12345">
        <Status>Fail</Status>
        <ErrorCode>1019</ErrorCode>
        <ErrorMessage>Statement is being generated, please try again shortly.</ErrorMessage>
      </FlexStatementResponse>
    XML
  end

  def error_generic_response
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <FlexStatementResponse timestamp="20260119;12345">
        <Status>Fail</Status>
        <ErrorCode>9999</ErrorCode>
        <ErrorMessage>Unknown error occurred.</ErrorMessage>
      </FlexStatementResponse>
    XML
  end

  # ============================================================
  # Successful Sync Tests
  # ============================================================

  test "perform_sync! fetches and parses positions successfully" do
    stub_request(:get, %r{/SendRequest})
      .to_return(status: 200, body: success_send_response)

    stub_request(:get, %r{/GetStatement})
      .to_return(status: 200, body: success_statement_response)

    result = @service.perform_sync!

    assert_equal 2, result[:positions].count # VTI and AAPL (LOT ignored)
    assert result[:errors].empty?
  end

  test "perform_sync! creates new positions" do
    stub_request(:get, %r{/SendRequest})
      .to_return(status: 200, body: success_send_response)

    stub_request(:get, %r{/GetStatement})
      .to_return(status: 200, body: success_statement_response)

    result = @service.perform_sync!

    assert_equal 2, @connection.broker_positions.count
    assert @connection.broker_positions.find_by(symbol: "VTI").present?
    assert @connection.broker_positions.find_by(symbol: "AAPL").present?
  end

  test "perform_sync! updates existing position values" do
    position = @connection.broker_positions.create!(
      symbol: "AAPL",
      description: "Old Description",
      currency: "USD",
      last_value: 1000,
      last_quantity: 10
    )

    stub_request(:get, %r{/SendRequest})
      .to_return(status: 200, body: success_send_response)

    stub_request(:get, %r{/GetStatement})
      .to_return(status: 200, body: success_statement_response)

    @service.perform_sync!

    position.reload
    assert_equal 8750.00, position.last_value.to_f
    assert_equal 50.0, position.last_quantity.to_f
    assert_equal "Apple Inc", position.description
  end

  test "perform_sync! updates connection last_synced_at on success" do
    @connection.update!(last_synced_at: 1.day.ago, last_sync_error: "old error")

    stub_request(:get, %r{/SendRequest})
      .to_return(status: 200, body: success_send_response)

    stub_request(:get, %r{/GetStatement})
      .to_return(status: 200, body: success_statement_response)

    @service.perform_sync!

    @connection.reload
    assert @connection.last_synced_at > 1.minute.ago
    assert_nil @connection.last_sync_error
  end

  test "perform_sync! filters out LOT level positions" do
    stub_request(:get, %r{/SendRequest})
      .to_return(status: 200, body: success_send_response)

    stub_request(:get, %r{/GetStatement})
      .to_return(status: 200, body: success_statement_response)

    result = @service.perform_sync!

    # Only SUMMARY level positions (VTI, AAPL) - not LOT positions
    symbols = result[:positions].map(&:symbol)
    assert_equal 2, symbols.count
    assert_includes symbols, "VTI"
    assert_includes symbols, "AAPL"
  end

  # ============================================================
  # Error Handling Tests
  # ============================================================

  test "perform_sync! raises AuthenticationError on auth failure" do
    stub_request(:get, %r{/SendRequest})
      .to_return(status: 200, body: error_auth_response)

    error = assert_raises BrokerSyncService::AuthenticationError do
      @service.perform_sync!
    end

    assert_includes error.message, "Authentication failed"

    @connection.reload
    assert_includes @connection.last_sync_error, "Authentication failed"
  end

  test "perform_sync! raises RateLimitError when rate limited" do
    stub_request(:get, %r{/SendRequest})
      .to_return(status: 200, body: error_rate_limit_response)

    error = assert_raises BrokerSyncService::RateLimitError do
      @service.perform_sync!
    end

    assert_includes error.message, "Rate limited"

    @connection.reload
    assert_includes @connection.last_sync_error, "Rate limited"
  end

  test "perform_sync! raises SyncError on generic API error" do
    stub_request(:get, %r{/SendRequest})
      .to_return(status: 200, body: error_generic_response)

    error = assert_raises BrokerSyncService::SyncError do
      @service.perform_sync!
    end

    assert_includes error.message, "9999"

    @connection.reload
    assert_includes @connection.last_sync_error, "9999"
  end

  test "perform_sync! raises SyncError on HTTP error" do
    stub_request(:get, %r{/SendRequest})
      .to_return(status: 500, body: "Internal Server Error")

    error = assert_raises BrokerSyncService::SyncError do
      @service.perform_sync!
    end

    assert_includes error.message, "HTTP error"

    @connection.reload
    assert_includes @connection.last_sync_error, "HTTP error"
  end

  test "perform_sync! retries when statement is being generated" do
    stub_request(:get, %r{/SendRequest})
      .to_return(status: 200, body: success_send_response)

    # First two attempts return "in progress", third succeeds
    stub_request(:get, %r{/GetStatement})
      .to_return(
        { status: 200, body: error_generation_in_progress_response },
        { status: 200, body: error_generation_in_progress_response },
        { status: 200, body: success_statement_response }
      )

    result = @service.perform_sync!

    assert result[:errors].empty?
    assert_equal 2, result[:positions].count
  end

  test "perform_sync! times out after max retries for generation in progress" do
    stub_request(:get, %r{/SendRequest})
      .to_return(status: 200, body: success_send_response)

    # All attempts return "in progress"
    stub_request(:get, %r{/GetStatement})
      .to_return(status: 200, body: error_generation_in_progress_response)

    error = assert_raises BrokerSyncService::SyncError do
      @service.perform_sync!
    end

    assert_includes error.message, "timed out"

    @connection.reload
    assert_includes @connection.last_sync_error, "timed out"
  end

  # ============================================================
  # XML Parsing Tests
  # ============================================================

  test "parse_positions extracts correct position data" do
    positions = @service.send(:parse_positions, success_statement_response)

    assert_equal 2, positions.count

    vti = positions.find { |p| p[:symbol] == "VTI" }
    assert_equal "VTI", vti[:symbol]
    assert_equal "Vanguard Total Stock Market ETF", vti[:description]
    assert_equal 100.0, vti[:quantity].to_f
    assert_equal 25000.00, vti[:value].to_f
    assert_equal "USD", vti[:currency]

    aapl = positions.find { |p| p[:symbol] == "AAPL" }
    assert_equal "AAPL", aapl[:symbol]
    assert_equal 50.0, aapl[:quantity].to_f
    assert_equal 8750.00, aapl[:value].to_f
  end

  test "parse_positions returns empty array for no positions" do
    empty_xml = <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <FlexQueryResponse>
        <FlexStatements count="1">
          <FlexStatement>
            <OpenPositions/>
          </FlexStatement>
        </FlexStatements>
      </FlexQueryResponse>
    XML

    positions = @service.send(:parse_positions, empty_xml)

    assert_equal [], positions
  end

  test "parse_positions handles markValue fallback" do
    xml_with_mark_value = <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <FlexQueryResponse>
        <FlexStatements count="1">
          <FlexStatement>
            <OpenPositions>
              <OpenPosition symbol="BOND" description="Some Bond"
                position="1000.0" markValue="99500.00" currency="USD" levelOfDetail="SUMMARY"/>
            </OpenPositions>
          </FlexStatement>
        </FlexStatements>
      </FlexQueryResponse>
    XML

    positions = @service.send(:parse_positions, xml_with_mark_value)

    assert_equal 1, positions.count
    assert_equal 99500.00, positions.first[:value].to_f
  end

  test "parse_positions extracts cash balances from Cash Report" do
    xml_with_cash = <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <FlexQueryResponse>
        <FlexStatements count="1">
          <FlexStatement>
            <OpenPositions>
              <OpenPosition symbol="VTI" description="Vanguard Total Stock Market ETF"
                position="100.0" positionValue="25000.00" currency="USD" levelOfDetail="SUMMARY"/>
            </OpenPositions>
            <CashReport>
              <CashReportCurrency currency="USD" endingCash="15000.50" endingSettledCash="15000.50"/>
              <CashReportCurrency currency="EUR" endingCash="5000.25" endingSettledCash="5000.25"/>
              <CashReportCurrency currency="BASE_SUMMARY" endingCash="20000.75" endingSettledCash="20000.75"/>
            </CashReport>
          </FlexStatement>
        </FlexStatements>
      </FlexQueryResponse>
    XML

    positions = @service.send(:parse_positions, xml_with_cash)

    assert_equal 3, positions.count # VTI + 2 cash positions (BASE_SUMMARY skipped)

    usd_cash = positions.find { |p| p[:symbol] == "USD" }
    assert_not_nil usd_cash
    assert_equal "Cash (USD)", usd_cash[:description]
    assert_equal 15000.50, usd_cash[:quantity].to_f
    assert_equal 15000.50, usd_cash[:value].to_f
    assert_equal "USD", usd_cash[:currency]

    eur_cash = positions.find { |p| p[:symbol] == "EUR" }
    assert_not_nil eur_cash
    assert_equal "Cash (EUR)", eur_cash[:description]
    assert_equal 5000.25, eur_cash[:quantity].to_f
    assert_equal "EUR", eur_cash[:currency]

    # BASE_SUMMARY should be skipped
    base_cash = positions.find { |p| p[:symbol] == "BASE_SUMMARY" }
    assert_nil base_cash
  end

  test "parse_positions skips zero cash balances" do
    xml_with_zero_cash = <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <FlexQueryResponse>
        <FlexStatements count="1">
          <FlexStatement>
            <OpenPositions/>
            <CashReport>
              <CashReportCurrency currency="USD" endingCash="1000.00" endingSettledCash="1000.00"/>
              <CashReportCurrency currency="EUR" endingCash="0" endingSettledCash="0"/>
              <CashReportCurrency currency="GBP" endingCash="0.00" endingSettledCash="0.00"/>
            </CashReport>
          </FlexStatement>
        </FlexStatements>
      </FlexQueryResponse>
    XML

    positions = @service.send(:parse_positions, xml_with_zero_cash)

    assert_equal 1, positions.count # Only USD cash (EUR and GBP are zero)
    assert_equal "USD", positions.first[:symbol]
  end

  # ============================================================
  # Request Building Tests
  # ============================================================

  test "request_report includes correct query parameters" do
    stub_request(:get, %r{/SendRequest})
      .with(query: hash_including(
        "t" => "test_token_abc123",
        "q" => "999999",
        "v" => "3"
      ))
      .to_return(status: 200, body: success_send_response)

    reference = @service.send(:request_report)

    assert_equal "REF123456", reference
  end

  test "fetch_report includes correct query parameters" do
    reference_code = "TEST123"

    stub_request(:get, %r{/GetStatement})
      .with(query: hash_including(
        "t" => "test_token_abc123",
        "q" => reference_code,
        "v" => "3"
      ))
      .to_return(status: 200, body: success_statement_response)

    response = @service.send(:fetch_report, reference_code)

    assert_includes response, "OpenPosition"
  end

  # ============================================================
  # Integration-like Tests
  # ============================================================

  test "full sync flow syncs mapped assets" do
    # Create an asset and map it to a position
    asset_group = AssetGroup.first || AssetGroup.create!(name: "Test Group", color: "#000000")
    asset_type = AssetType.first || AssetType.create!(name: "Test Type", is_liability: false)

    asset = Asset.create!(
      name: "Test Stock Portfolio",
      asset_type: asset_type,
      asset_group: asset_group,
      currency: "USD",
      value: 0
    )

    position = @connection.broker_positions.create!(
      symbol: "AAPL",
      description: "Apple",
      currency: "USD",
      asset: asset
    )

    stub_request(:get, %r{/SendRequest})
      .to_return(status: 200, body: success_send_response)

    stub_request(:get, %r{/GetStatement})
      .to_return(status: 200, body: success_statement_response)

    result = @service.perform_sync!

    # Asset value should be updated to position value
    assert result[:updated_count] > 0
    asset.reload
    assert_equal 8750.00, asset.value.to_f
  end

  test "sync records position valuations" do
    stub_request(:get, %r{/SendRequest})
      .to_return(status: 200, body: success_send_response)

    stub_request(:get, %r{/GetStatement})
      .to_return(status: 200, body: success_statement_response)

    initial_count = PositionValuation.count

    @service.sync! # Note: sync! not perform_sync! - includes valuations

    # Should have created valuations for each position (2 positions)
    assert_equal initial_count + 2, PositionValuation.count
  end

  # ============================================================
  # Position Closing Tests
  # ============================================================

  test "perform_sync! closes positions that disappear from broker" do
    # Create a position that won't be in the sync response
    old_position = @connection.broker_positions.create!(
      symbol: "GOOG",
      description: "Alphabet Inc",
      currency: "USD",
      last_value: 5000,
      last_quantity: 10
    )

    stub_request(:get, %r{/SendRequest})
      .to_return(status: 200, body: success_send_response)

    stub_request(:get, %r{/GetStatement})
      .to_return(status: 200, body: success_statement_response)

    result = @service.perform_sync!

    # GOOG should be closed since it wasn't in the response
    old_position.reload
    assert old_position.closed?
    assert_equal 0, old_position.last_value
    assert_equal 0, old_position.last_quantity
    assert_equal 1, result[:closed_count]
  end

  test "perform_sync! does not close positions that are in the sync" do
    # Create a position that WILL be in the sync response
    existing_position = @connection.broker_positions.create!(
      symbol: "AAPL",
      description: "Apple Inc",
      currency: "USD",
      last_value: 1000,
      last_quantity: 5
    )

    stub_request(:get, %r{/SendRequest})
      .to_return(status: 200, body: success_send_response)

    stub_request(:get, %r{/GetStatement})
      .to_return(status: 200, body: success_statement_response)

    @service.perform_sync!

    existing_position.reload
    assert existing_position.open?
    assert_equal 8750.00, existing_position.last_value.to_f # Updated from sync
  end

  test "perform_sync! reopens previously closed positions that reappear" do
    # Create a closed position that will reappear in the sync
    closed_position = @connection.broker_positions.create!(
      symbol: "VTI",
      description: "Vanguard ETF",
      currency: "USD",
      last_value: 0,
      last_quantity: 0,
      closed_at: 1.week.ago
    )

    stub_request(:get, %r{/SendRequest})
      .to_return(status: 200, body: success_send_response)

    stub_request(:get, %r{/GetStatement})
      .to_return(status: 200, body: success_statement_response)

    @service.perform_sync!

    closed_position.reload
    assert closed_position.open?
    assert_nil closed_position.closed_at
    assert_equal 25000.00, closed_position.last_value.to_f # Updated from sync
  end

  test "perform_sync! does not close already closed positions" do
    already_closed = @connection.broker_positions.create!(
      symbol: "OLD",
      description: "Old Position",
      currency: "USD",
      last_value: 0,
      last_quantity: 0,
      closed_at: 1.month.ago
    )
    original_closed_at = already_closed.closed_at

    stub_request(:get, %r{/SendRequest})
      .to_return(status: 200, body: success_send_response)

    stub_request(:get, %r{/GetStatement})
      .to_return(status: 200, body: success_statement_response)

    result = @service.perform_sync!

    already_closed.reload
    # Should still be closed, closed_at unchanged
    assert already_closed.closed?
    # closed_count should only count newly closed positions
    assert_equal 0, result[:closed_count]
  end
end

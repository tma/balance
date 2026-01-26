require "test_helper"

class BrokerSyncJobTest < ActiveJob::TestCase
  # Testable subclass that skips sleep
  class TestableJob < BrokerSyncJob
    # Override sleep to be a no-op
    def sleep(_seconds)
      # No-op in tests
    end
  end

  # Testable service that skips sleep
  class TestableIbkrSyncService < IbkrSyncService
    private

    def wait(_seconds)
      # No-op in tests
    end
  end

  setup do
    @connection = BrokerConnection.create!(
      broker_type: :ibkr,
      account_id: "U9999999",
      name: "Test IBKR Account",
      flex_token: "test_token_abc123",
      flex_query_id: "999999"
    )

    # Stub HTTP requests
    WebMock.disable_net_connect!

    # Stub Frankfurter API for currency conversion
    stub_request(:get, %r{api\.frankfurter\.app})
      .to_return(status: 200, body: { rates: { "EUR" => 0.85, "USD" => 1.0 } }.to_json,
                 headers: { "Content-Type" => "application/json" })

    # Stub IBKR API
    stub_request(:get, %r{/SendRequest})
      .to_return(status: 200, body: success_send_response)

    stub_request(:get, %r{/GetStatement})
      .to_return(status: 200, body: success_statement_response)

    # Make BrokerSyncService.for return our testable service
    BrokerSyncService.define_singleton_method(:for) do |connection|
      TestableIbkrSyncService.new(connection)
    end
  end

  teardown do
    WebMock.reset!
    WebMock.allow_net_connect!

    # Restore original factory method
    BrokerSyncService.define_singleton_method(:for) do |connection|
      case connection.broker_type
      when "ibkr"
        IbkrSyncService.new(connection)
      else
        raise BrokerSyncService::SyncError, "Unknown broker type: #{connection.broker_type}"
      end
    end
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

  # ============================================================
  # Gap Detection Tests
  # ============================================================

  test "dates_to_sync_for returns only today when last_sync_date is nil and no valuations" do
    job = TestableJob.new

    dates = job.send(:dates_to_sync_for, @connection)

    assert_equal [ Date.current ], dates
  end

  test "dates_to_sync_for returns gap dates plus today when last_sync_date is set" do
    @connection.update!(last_sync_date: Date.current - 3.days)
    job = TestableJob.new

    dates = job.send(:dates_to_sync_for, @connection)

    # Should include 2 days ago, yesterday, and today (3 dates total)
    assert_equal 3, dates.count
    assert_equal Date.current - 2.days, dates.first
    assert_equal Date.current, dates.last
  end

  test "dates_to_sync_for returns empty array when already synced today" do
    @connection.update!(last_sync_date: Date.current)
    job = TestableJob.new

    dates = job.send(:dates_to_sync_for, @connection)

    assert_equal [], dates
  end

  test "dates_to_sync_for caps at MAX_BACKFILL_DAYS" do
    @connection.update!(last_sync_date: Date.current - 100.days)
    job = TestableJob.new

    dates = job.send(:dates_to_sync_for, @connection)

    assert_equal BrokerSyncJob::MAX_BACKFILL_DAYS, dates.count
    # Should sync most recent 90 days, ending with today
    assert_equal Date.current, dates.last
  end

  test "dates_to_sync_for falls back to last valuation date when last_sync_date is nil" do
    # Create a position with a valuation
    position = @connection.broker_positions.create!(
      symbol: "VTI",
      description: "Vanguard",
      currency: "USD",
      last_value: 25000,
      last_quantity: 100
    )
    position.position_valuations.create!(
      date: Date.current - 5.days,
      quantity: 100,
      value: 25000,
      currency: "USD"
    )

    job = TestableJob.new

    dates = job.send(:dates_to_sync_for, @connection)

    # Should backfill from day after last valuation
    assert_equal 5, dates.count
    assert_equal Date.current - 4.days, dates.first
    assert_equal Date.current, dates.last
  end

  # ============================================================
  # Sync Execution Tests
  # ============================================================

  test "perform syncs all connections" do
    TestableJob.perform_now

    @connection.reload
    assert_equal Date.current, @connection.last_sync_date
  end

  test "perform updates last_sync_date after successful sync" do
    assert_nil @connection.last_sync_date

    TestableJob.perform_now

    @connection.reload
    assert_equal Date.current, @connection.last_sync_date
  end

  test "perform continues to next connection if one fails" do
    # Create a second connection
    connection2 = BrokerConnection.create!(
      broker_type: :ibkr,
      account_id: "U8888888",
      name: "Second Account",
      flex_token: "test_token_2",
      flex_query_id: "888888"
    )

    # Reset stubs
    WebMock.reset!

    # Stub Frankfurter API
    stub_request(:get, %r{api\.frankfurter\.app})
      .to_return(status: 200, body: { rates: { "EUR" => 0.85, "USD" => 1.0 } }.to_json,
                 headers: { "Content-Type" => "application/json" })

    # First connection will fail
    stub_request(:get, %r{/SendRequest})
      .with(query: hash_including("q" => "999999"))
      .to_return(status: 200, body: error_auth_response)

    # Second connection will succeed
    stub_request(:get, %r{/SendRequest})
      .with(query: hash_including("q" => "888888"))
      .to_return(status: 200, body: success_send_response)

    stub_request(:get, %r{/GetStatement})
      .to_return(status: 200, body: success_statement_response)

    TestableJob.perform_now

    # First connection should have error
    @connection.reload
    assert @connection.last_sync_error.present?
    assert_nil @connection.last_sync_date

    # Second connection should succeed
    connection2.reload
    assert_nil connection2.last_sync_error
    assert_equal Date.current, connection2.last_sync_date
  ensure
    connection2&.destroy
  end

  # ============================================================
  # Error Handling Tests
  # ============================================================

  test "sync error records error on connection but does not raise" do
    WebMock.reset!

    stub_request(:get, %r{api\.frankfurter\.app})
      .to_return(status: 200, body: { rates: { "EUR" => 0.85, "USD" => 1.0 } }.to_json,
                 headers: { "Content-Type" => "application/json" })

    stub_request(:get, %r{/SendRequest})
      .to_return(status: 200, body: error_auth_response)

    # Should not raise
    assert_nothing_raised do
      TestableJob.perform_now
    end

    @connection.reload
    assert @connection.last_sync_error.present?
    assert_includes @connection.last_sync_error, "Authentication failed"
  end
end

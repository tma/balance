require "test_helper"

class BrokerSyncJobTest < ActiveJob::TestCase
  setup do
    @connection = BrokerConnection.create!(
      broker_type: :ibkr,
      account_id: "U9999999",
      name: "Test IBKR Account",
      flex_token: "test_token_abc123",
      flex_query_id: "999999"
    )
  end

  teardown do
    @connection.destroy if @connection.persisted?
  end

  # ============================================================
  # Sync Execution Tests
  # ============================================================

  test "perform syncs all connections" do
    original_sync_missing = BrokerSyncBackfillService.method(:sync_missing_dates!)
    BrokerSyncBackfillService.define_singleton_method(:sync_missing_dates!) do |connection|
      connection.update!(last_synced_at: Time.current)
      { dates: [ Date.current ], synced: 1 }
    end

    BrokerSyncJob.perform_now

    @connection.reload
    assert @connection.last_synced_at.present?
  ensure
    BrokerSyncBackfillService.define_singleton_method(:sync_missing_dates!) do |*args, **kwargs, &block|
      original_sync_missing.call(*args, **kwargs, &block)
    end
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

    original_sync_missing = BrokerSyncBackfillService.method(:sync_missing_dates!)
    BrokerSyncBackfillService.define_singleton_method(:sync_missing_dates!) do |connection|
      if connection.account_id == "U9999999"
        connection.update!(last_sync_error: "Authentication failed")
        raise BrokerSyncService::AuthenticationError, "Authentication failed"
      else
        connection.update!(last_sync_error: nil, last_synced_at: Time.current)
        { dates: [ Date.current ], synced: 1 }
      end
    end

    BrokerSyncJob.perform_now

    # First connection should have error
    @connection.reload
    assert @connection.last_sync_error.present?
    assert_nil @connection.last_synced_at

    # Second connection should succeed
    connection2.reload
    assert_nil connection2.last_sync_error
    assert connection2.last_synced_at.present?
  ensure
    connection2&.destroy
    BrokerSyncBackfillService.define_singleton_method(:sync_missing_dates!) do |*args, **kwargs, &block|
      original_sync_missing.call(*args, **kwargs, &block)
    end
  end

  # ============================================================
  # Error Handling Tests
  # ============================================================

  test "sync error records error on connection but does not raise" do
    WebMock.reset!

    stub_request(:get, %r{api\.frankfurter\.app})
      .to_return(status: 200, body: { rates: { "EUR" => 0.85, "USD" => 1.0 } }.to_json,
                 headers: { "Content-Type" => "application/json" })

    original_sync_missing = BrokerSyncBackfillService.method(:sync_missing_dates!)
    BrokerSyncBackfillService.define_singleton_method(:sync_missing_dates!) do |connection|
      connection.update!(last_sync_error: "Authentication failed")
      raise BrokerSyncService::AuthenticationError, "Authentication failed"
    end

    # Should not raise
    assert_nothing_raised do
      BrokerSyncJob.perform_now
    end

    @connection.reload
    assert @connection.last_sync_error.present?
    assert_includes @connection.last_sync_error, "Authentication failed"
  ensure
    BrokerSyncBackfillService.define_singleton_method(:sync_missing_dates!) do |*args, **kwargs, &block|
      original_sync_missing.call(*args, **kwargs, &block)
    end
  end
end

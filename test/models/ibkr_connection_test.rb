require "test_helper"

class IbkrConnectionTest < ActiveSupport::TestCase
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
  # days_behind tests
  # ============================================================

  test "days_behind returns nil when last_sync_date is nil" do
    assert_nil @connection.days_behind
  end

  test "days_behind returns 0 when synced today" do
    @connection.update!(last_sync_date: Date.current)
    assert_equal 0, @connection.days_behind
  end

  test "days_behind returns correct number of days" do
    @connection.update!(last_sync_date: Date.current - 5.days)
    assert_equal 5, @connection.days_behind
  end

  # ============================================================
  # sync_status tests
  # ============================================================

  test "sync_status returns :never when never synced" do
    assert_equal :never, @connection.sync_status
  end

  test "sync_status returns :error when last_sync_error is present" do
    @connection.update!(last_synced_at: 1.day.ago, last_sync_error: "Some error")
    assert_equal :error, @connection.sync_status
  end

  test "sync_status returns :behind when more than 1 day behind" do
    @connection.update!(last_synced_at: 1.day.ago, last_sync_date: Date.current - 3.days)
    assert_equal :behind, @connection.sync_status
  end

  test "sync_status returns :ok when synced and up to date" do
    @connection.update!(last_synced_at: 1.hour.ago, last_sync_date: Date.current)
    assert_equal :ok, @connection.sync_status
  end

  test "sync_status returns :ok when synced yesterday (1 day behind is acceptable)" do
    @connection.update!(last_synced_at: 1.day.ago, last_sync_date: Date.current - 1.day)
    assert_equal :ok, @connection.sync_status
  end

  # ============================================================
  # sync_status_label tests
  # ============================================================

  test "sync_status_label returns 'Never synced' when never synced" do
    assert_equal "Never synced", @connection.sync_status_label
  end

  test "sync_status_label returns error message when error" do
    @connection.update!(last_synced_at: 1.day.ago, last_sync_error: "Authentication failed")
    assert_includes @connection.sync_status_label, "Failed:"
    assert_includes @connection.sync_status_label, "Authentication failed"
  end

  test "sync_status_label truncates long error messages" do
    long_error = "A" * 100
    @connection.update!(last_synced_at: 1.day.ago, last_sync_error: long_error)
    assert @connection.sync_status_label.length < 70
  end

  test "sync_status_label returns days behind when behind" do
    @connection.update!(last_synced_at: 1.day.ago, last_sync_date: Date.current - 5.days)
    assert_equal "5 days behind", @connection.sync_status_label
  end

  test "sync_status_label returns 'Synced' when ok" do
    @connection.update!(last_synced_at: 1.hour.ago, last_sync_date: Date.current)
    assert_equal "Synced", @connection.sync_status_label
  end
end

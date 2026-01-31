require "test_helper"

class BrokerSyncBackfillServiceTest < ActiveSupport::TestCase
  test "missing_dates_for returns empty when no open positions" do
    connection = BrokerConnection.create!(
      broker_type: :ibkr,
      name: "Empty Connection",
      flex_token: "token",
      flex_query_id: "111111"
    )

    travel_to Date.new(2026, 1, 19) do
      assert_equal [], BrokerSyncBackfillService.missing_dates_for(connection)
    end
  ensure
    connection&.destroy
  end

  test "sync_missing_dates syncs today when no open positions" do
    connection = BrokerConnection.create!(
      broker_type: :ibkr,
      name: "Empty Sync",
      flex_token: "token",
      flex_query_id: "222222"
    )
    service = Class.new do
      attr_reader :dates

      def initialize
        @dates = []
      end

      def sync!(sync_date:)
        @dates << sync_date
      end
    end.new

    original_pause = BrokerSyncBackfillService.method(:pause)
    original_for = BrokerSyncService.method(:for)

    BrokerSyncBackfillService.define_singleton_method(:pause) { |_seconds| }
    BrokerSyncService.define_singleton_method(:for) { |_connection| service }

    travel_to Date.new(2026, 1, 19) do
      result = BrokerSyncBackfillService.sync_missing_dates!(connection)

      assert_equal [ Date.current ], service.dates
      assert_equal 1, result[:synced]
    end
  ensure
    BrokerSyncBackfillService.define_singleton_method(:pause) do |*args, **kwargs, &block|
      original_pause.call(*args, **kwargs, &block)
    end
    BrokerSyncService.define_singleton_method(:for) do |*args, **kwargs, &block|
      original_for.call(*args, **kwargs, &block)
    end
    connection&.destroy
  end

  test "missing_dates_for is strict across open positions" do
    connection = broker_connections(:one)

    travel_to Date.new(2026, 1, 19) do
      connection.broker_positions.open.update_all(created_at: Time.zone.local(2026, 1, 17, 10, 0, 0))
      missing_dates = BrokerSyncBackfillService.missing_dates_for(connection)

      assert_includes missing_dates, Date.new(2026, 1, 19)
      assert_not_includes missing_dates, Date.new(2026, 1, 18)
    end
  end

  test "missing_dates_for ignores dates before position existed" do
    connection = broker_connections(:one)
    position = broker_positions(:aapl_position)

    position.update!(created_at: Date.new(2026, 1, 19))

    travel_to Date.new(2026, 1, 19) do
      missing_dates = BrokerSyncBackfillService.missing_dates_for(connection)

      assert_not_includes missing_dates, Date.new(2026, 1, 17)
      assert_not_includes missing_dates, Date.new(2026, 1, 18)
      assert_includes missing_dates, Date.new(2026, 1, 19)
    end
  end

  test "sync_missing_dates syncs each missing date in order" do
    connection = broker_connections(:one)
    service = Class.new do
      attr_reader :dates

      def initialize
        @dates = []
      end

      def sync!(sync_date:)
        @dates << sync_date
      end
    end.new

    missing_dates = [ Date.new(2026, 1, 18), Date.new(2026, 1, 19) ]

    original_missing = BrokerSyncBackfillService.method(:missing_dates_for)
    original_pause = BrokerSyncBackfillService.method(:pause)
    original_for = BrokerSyncService.method(:for)

    BrokerSyncBackfillService.define_singleton_method(:missing_dates_for) { |_conn, window_days:| missing_dates }
    BrokerSyncBackfillService.define_singleton_method(:pause) { |_seconds| }
    BrokerSyncService.define_singleton_method(:for) { |_connection| service }

    travel_to Date.new(2026, 1, 19) do
      result = BrokerSyncBackfillService.sync_missing_dates!(connection)

      assert_equal missing_dates, service.dates
      assert_equal 2, result[:synced]
    end
  ensure
    BrokerSyncBackfillService.define_singleton_method(:missing_dates_for) do |*args, **kwargs, &block|
      original_missing.call(*args, **kwargs, &block)
    end
    BrokerSyncBackfillService.define_singleton_method(:pause) do |*args, **kwargs, &block|
      original_pause.call(*args, **kwargs, &block)
    end
    BrokerSyncService.define_singleton_method(:for) do |*args, **kwargs, &block|
      original_for.call(*args, **kwargs, &block)
    end
  end
end

require "set"

class BrokerSyncBackfillService
  WINDOW_DAYS = 14
  BACKFILL_DELAY = 5.seconds

  def self.sync_missing_dates!(connection, window_days: WINDOW_DAYS, current_first: false)
    dates = missing_dates_for(connection, window_days: window_days)

    # Always include today to get latest values (markets may still be open)
    dates << Date.current unless dates.include?(Date.current)
    dates = ordered_sync_dates(dates, current_first: current_first)

    return { dates: [], synced: 0, results: [] } if dates.empty?

    service = BrokerSyncService.for(connection)
    results = []

    dates.each_with_index do |date, index|
      pause(BACKFILL_DELAY) if index.positive?
      sync_result = service.sync!(sync_date: date)
      results << { date: date, result: sync_result }
    end

    { dates: dates, synced: dates.count, results: results }
  end

  def self.missing_dates_for(connection, window_days: WINDOW_DAYS)
    return [] unless connection.supports_historical_sync?

    end_date = Date.current
    start_date = end_date - (window_days - 1).days
    open_positions = connection.broker_positions.open

    return [] if open_positions.empty?

    position_starts = open_positions.pluck(:id, :created_at).to_h
    position_ids = position_starts.keys
    return [] if position_ids.empty?

    valuations = PositionValuation
                 .where(broker_position_id: position_ids, date: start_date..end_date)
                 .pluck(:date, :broker_position_id)

    valuations_by_date = Hash.new { |hash, key| hash[key] = Set.new }
    valuations.each do |date, position_id|
      valuations_by_date[date] << position_id
    end

    (start_date..end_date).select do |date|
      expected_count = position_starts.count { |_id, created_at| created_at.to_date <= date }
      actual_count = valuations_by_date[date].size
      actual_count < expected_count
    end
  end

  def self.pause(seconds)
    sleep(seconds)
  end

  def self.ordered_sync_dates(dates, current_first:)
    dates = dates.uniq
    return dates unless current_first

    [ Date.current, *dates.reject { |date| date == Date.current } ]
  end
end

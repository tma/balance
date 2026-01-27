require "set"

class BrokerSyncBackfillService
  WINDOW_DAYS = 14
  BACKFILL_DELAY = 5.seconds

  def self.sync_missing_dates!(connection, window_days: WINDOW_DAYS)
    dates = missing_dates_for(connection, window_days: window_days)

    if dates.empty? && connection.broker_positions.open.none?
      dates = [ Date.current ]
    end

    return { dates: [], synced: 0 } if dates.empty?

    service = BrokerSyncService.for(connection)

    dates.each_with_index do |date, index|
      pause(BACKFILL_DELAY) if index.positive?
      service.sync!(sync_date: date)
    end

    { dates: dates, synced: dates.count }
  end

  def self.missing_dates_for(connection, window_days: WINDOW_DAYS)
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
end

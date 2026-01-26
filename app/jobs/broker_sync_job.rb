# Scheduled job to sync all broker connections and record position valuations
# Runs daily at 5pm ET (1 hour after NYSE close) via Solid Queue recurring schedule
#
# Features:
# - Gap detection: identifies missed sync days and backfills them
# - Rate limiting: 5 second delay between requests to avoid IBKR rate limits
# - Fallback: if last_sync_date is nil, looks up last valuation date
class BrokerSyncJob < ApplicationJob
  queue_as :default

  BACKFILL_DELAY = 5.seconds
  MAX_BACKFILL_DAYS = 90

  def perform
    Rails.logger.info "[BrokerSyncJob] Starting daily broker sync"

    BrokerConnection.find_each do |connection|
      sync_connection_with_backfill(connection)
    end

    Rails.logger.info "[BrokerSyncJob] Completed daily broker sync"
  end

  private

  def sync_connection_with_backfill(connection)
    dates = dates_to_sync_for(connection)

    if dates.empty?
      Rails.logger.info "[BrokerSyncJob] #{connection.name}: already up to date"
      return
    end

    Rails.logger.info "[BrokerSyncJob] #{connection.name}: #{dates.count} date(s) to sync"

    dates.each_with_index do |date, index|
      sleep(BACKFILL_DELAY) if index > 0 # Rate limit between requests
      sync_for_date(connection, date)
    end
  rescue BrokerSyncService::SyncError => e
    Rails.logger.error "[BrokerSyncJob] #{connection.name}: sync failed - #{e.message}"
    # Error recorded on connection; will retry as gap tomorrow
  rescue StandardError => e
    Rails.logger.error "[BrokerSyncJob] #{connection.name}: unexpected error - #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end

  def dates_to_sync_for(connection)
    last_date = connection.last_sync_date || last_valuation_date_for(connection)

    if last_date.nil?
      # Truly first sync ever - just sync today
      [ Date.current ]
    else
      gap_start = last_date + 1.day
      all_dates = (gap_start..Date.current).to_a

      # Cap at MAX_BACKFILL_DAYS to avoid excessive API calls
      if all_dates.size > MAX_BACKFILL_DAYS
        Rails.logger.warn "[BrokerSyncJob] #{connection.name}: gap of #{all_dates.size} days exceeds max, limiting to #{MAX_BACKFILL_DAYS}"
        all_dates.last(MAX_BACKFILL_DAYS)
      else
        all_dates
      end
    end
  end

  # Look up the most recent valuation date from existing position valuations
  # Used when last_sync_date is nil but valuations exist (e.g., migration scenario)
  def last_valuation_date_for(connection)
    connection.broker_positions
              .joins(:position_valuations)
              .maximum("position_valuations.date")
  end

  def sync_for_date(connection, date)
    Rails.logger.info "[BrokerSyncJob] #{connection.name}: syncing #{date}"

    service = BrokerSyncService.for(connection)
    result = service.sync!(sync_date: date)

    connection.update!(last_sync_date: date)

    Rails.logger.info "[BrokerSyncJob] #{connection.name}: synced #{result[:positions].count} positions for #{date}"
  end
end

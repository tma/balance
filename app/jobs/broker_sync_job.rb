# Scheduled job to sync all broker connections and record position valuations
# Runs daily at 5pm ET (1 hour after NYSE close) via Solid Queue recurring schedule
#
# Features:
# - Gap detection: identifies missing valuation days in the last 14 days
# - Rate limiting: 5 second delay between requests to avoid IBKR rate limits
class BrokerSyncJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "[BrokerSyncJob] Starting daily broker sync"

    BrokerConnection.find_each do |connection|
      sync_connection_with_backfill(connection)
    end

    Rails.logger.info "[BrokerSyncJob] Completed daily broker sync"
  end

  private

  def sync_connection_with_backfill(connection)
    result = BrokerSyncBackfillService.sync_missing_dates!(connection)
    return if result[:dates].empty?

    Rails.logger.info "[BrokerSyncJob] #{connection.name}: synced #{result[:synced]} date(s)"
  rescue BrokerSyncService::SyncError => e
    Rails.logger.error "[BrokerSyncJob] #{connection.name}: sync failed - #{e.message}"
    # Error recorded on connection; will retry as gap tomorrow
  rescue StandardError => e
    Rails.logger.error "[BrokerSyncJob] #{connection.name}: unexpected error - #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end
end

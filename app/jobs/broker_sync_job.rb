# Scheduled job to sync all broker connections and record position valuations
# Runs daily at 11:30pm via Solid Queue recurring schedule
class BrokerSyncJob < ApplicationJob
  queue_as :default

  # Retry on transient errors (network issues, API timeouts, etc.)
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform
    Rails.logger.info "[BrokerSyncJob] Starting daily broker sync"

    BrokerConnection.find_each do |connection|
      sync_connection(connection)
    end

    Rails.logger.info "[BrokerSyncJob] Completed daily broker sync"
  end

  private

  def sync_connection(connection)
    Rails.logger.info "[BrokerSyncJob] Syncing #{connection.name} (#{connection.broker_type})"

    service = BrokerSyncService.for(connection)
    result = service.sync!

    Rails.logger.info "[BrokerSyncJob] #{connection.name}: synced #{result[:positions].count} positions, updated #{result[:updated_count]} assets"
  rescue BrokerSyncService::SyncError => e
    Rails.logger.error "[BrokerSyncJob] #{connection.name}: sync failed - #{e.message}"
  rescue StandardError => e
    Rails.logger.error "[BrokerSyncJob] #{connection.name}: unexpected error - #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end
end

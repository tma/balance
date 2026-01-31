# Factory class for broker-specific sync services
# Usage: BrokerSyncService.for(connection).sync!
class BrokerSyncService
  class SyncError < StandardError; end
  class AuthenticationError < SyncError; end
  class RateLimitError < SyncError; end

  # Factory method to get the appropriate service for a connection
  def self.for(connection)
    case connection.broker_type
    when "ibkr"
      IbkrSyncService.new(connection)
    when "manual"
      ManualSyncService.new(connection)
    else
      raise SyncError, "Unknown broker type: #{connection.broker_type}"
    end
  end

  def initialize(connection)
    @connection = connection
  end

  # Sync positions from broker, update mappings, and record position valuations
  # Returns { positions: [...], updated_count: N, errors: [...] }
  # @param sync_date [Date, nil] The date to sync data for (defaults to today)
  def sync!(sync_date: nil)
    date = sync_date || Date.current
    result = perform_sync!(sync_date: date)

    # Record position valuations for historical tracking
    # (subclasses may handle this inline during perform_sync! by overriding records_valuations_inline?)
    record_position_valuations!(date: date) unless records_valuations_inline?

    result
  end

  protected

  # Subclasses must implement this method to perform the actual sync
  # Returns { positions: [...], updated_count: N, errors: [...] }
  # @param sync_date [Date, nil] The date to sync data for
  def perform_sync!(sync_date: nil)
    raise NotImplementedError, "Subclasses must implement perform_sync!"
  end

  # Override in subclasses that record valuations inline during perform_sync!
  # (e.g., when broker provides FX rates that need to be passed through)
  def records_valuations_inline?
    false
  end

  # Update all assets that have mappings from this connection
  # An asset may have multiple mappings (from this or other connections)
  # so we need to sum all of them with currency conversion
  def sync_mapped_assets
    asset_ids = @connection.mapped_positions.pluck(:asset_id).uniq
    assets = Asset.where(id: asset_ids)

    assets.each(&:sync_from_broker_positions!)
    assets
  end

  # Record a valuation snapshot for each position
  # @param date [Date] The date to record valuations for
  def record_position_valuations!(date:)
    @connection.broker_positions.each do |position|
      position.record_valuation!(date: date)
    end
  end
end

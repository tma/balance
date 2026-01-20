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
    else
      raise SyncError, "Unknown broker type: #{connection.broker_type}"
    end
  end

  def initialize(connection)
    @connection = connection
  end

  # Sync positions from broker, update mappings, and record position valuations
  # Returns { positions: [...], updated_count: N, errors: [...] }
  def sync!
    result = perform_sync!

    # Enrich position descriptions from Twelve Data
    enrich_position_descriptions!

    # Record position valuations for historical tracking
    record_position_valuations!

    result
  end

  protected

  # Subclasses must implement this method to perform the actual sync
  # Returns { positions: [...], updated_count: N, errors: [...] }
  def perform_sync!
    raise NotImplementedError, "Subclasses must implement perform_sync!"
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
  def record_position_valuations!
    @connection.broker_positions.each do |position|
      position.record_valuation!(date: Date.current)
    end
  end

  # Enrich position descriptions using Twelve Data API
  # Only updates positions with ugly broker descriptions (all uppercase)
  def enrich_position_descriptions!
    @connection.broker_positions.open.each do |position|
      next unless needs_description_update?(position)

      new_description = TwelveDataService.lookup_name(position.symbol, currency: position.currency)
      if new_description.present? && new_description != position.description
        position.update!(description: new_description)
        Rails.logger.info "[BrokerSync] Updated description for #{position.symbol}: #{new_description}"
      end
    rescue StandardError => e
      # Don't fail sync if description lookup fails
      Rails.logger.warn "[BrokerSync] Failed to enrich description for #{position.symbol}: #{e.message}"
    end
  end

  private

  # Check if a position's description needs updating
  # Returns true if description is all uppercase or very short
  def needs_description_update?(position)
    return true if position.description.blank?

    # Skip cash positions (e.g., "Cash (USD)")
    return false if position.description.start_with?("Cash (")

    # Update if description is all uppercase (typical broker format)
    position.description == position.description.upcase
  end
end

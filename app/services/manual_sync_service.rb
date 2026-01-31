require "net/http"
require "json"

# Manual broker sync service that fetches crypto prices from CoinGecko
class ManualSyncService < BrokerSyncService
  COINGECKO_API_BASE = "https://api.coingecko.com/api/v3"

  def perform_sync!(sync_date: nil)
    result = { positions: [], updated_count: 0, closed_count: 0, errors: [] }
    valuation_date = sync_date || Date.current

    begin
      # Get crypto positions that can be priced
      crypto_positions = @connection.broker_positions.open.select(&:crypto_position?)
      return result if crypto_positions.empty?

      # Batch fetch prices from CoinGecko
      coingecko_ids = crypto_positions.map(&:coingecko_id).uniq
      prices = fetch_crypto_prices(coingecko_ids)

      # Update each position
      crypto_positions.each do |position|
        price = prices[position.coingecko_id]
        next unless price

        # Calculate value from quantity and price
        quantity = position.last_quantity || 0
        value = (quantity * price).round(2)

        position.update!(
          last_value: value,
          last_synced_at: Time.current
        )

        record_position_valuation!(position, date: valuation_date)
        result[:positions] << position
      end

      result[:updated_count] = result[:positions].count

      # Update mapped assets
      sync_mapped_assets

      @connection.update!(last_synced_at: Time.current, last_sync_error: nil)
    rescue SyncError => e
      @connection.update!(last_sync_error: e.message)
      result[:errors] << e.message
      raise
    rescue StandardError => e
      @connection.update!(last_sync_error: "Unexpected error: #{e.message}")
      result[:errors] << e.message
      raise SyncError, e.message
    end

    result
  end

  def test_connection
    response = fetch_crypto_prices([ "bitcoin" ])
    if response["bitcoin"].present?
      { success: true, message: "CoinGecko API reachable", btc_price: response["bitcoin"] }
    else
      { success: false, error: "Could not fetch Bitcoin price" }
    end
  rescue => e
    { success: false, error: e.message }
  end

  private

  def records_valuations_inline?
    true
  end

  def fetch_crypto_prices(coingecko_ids)
    return {} if coingecko_ids.empty?

    uri = URI("#{COINGECKO_API_BASE}/simple/price")
    uri.query = URI.encode_www_form(
      ids: coingecko_ids.join(","),
      vs_currencies: "usd"
    )

    response = Net::HTTP.get_response(uri)

    unless response.is_a?(Net::HTTPSuccess)
      raise SyncError, "CoinGecko API error: #{response.code}"
    end

    data = JSON.parse(response.body)

    # Transform to { "bitcoin" => 87234.0, "ethereum" => 3456.0 }
    data.transform_values { |v| v["usd"]&.to_f }
  rescue JSON::ParserError => e
    raise SyncError, "Invalid response from CoinGecko: #{e.message}"
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    raise SyncError, "CoinGecko API timeout: #{e.message}"
  rescue SocketError, Errno::ECONNREFUSED => e
    raise SyncError, "CoinGecko API unreachable: #{e.message}"
  end

  def record_position_valuation!(position, date:)
    return unless position.last_quantity.present?

    valuation = position.position_valuations.find_or_initialize_by(date: date)
    valuation.assign_attributes(
      quantity: position.last_quantity,
      value: position.last_value,
      currency: position.currency || "USD"
    )
    valuation.save!
  end
end

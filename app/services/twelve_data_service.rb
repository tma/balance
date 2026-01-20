# Service for looking up security information from Twelve Data API
# https://twelvedata.com/docs
#
# Free tier: No API key required for symbol search
class TwelveDataService
  BASE_URL = "https://api.twelvedata.com"

  class Error < StandardError; end

  # Look up instrument name for a symbol
  # Returns the best matching instrument_name or nil if not found
  #
  # @param symbol [String] The ticker symbol (e.g., "AAPL", "IB01")
  # @param currency [String, nil] Optional currency to filter results (e.g., "USD")
  # @return [String, nil] The instrument name or nil
  def self.lookup_name(symbol, currency: nil)
    new.lookup_name(symbol, currency: currency)
  end

  def lookup_name(symbol, currency: nil)
    return nil if symbol.blank?

    results = search_symbol(symbol)
    return nil if results.empty?

    # Find best match: exact symbol match, preferring matching currency
    exact_matches = results.select { |r| r["symbol"].upcase == symbol.upcase }
    return nil if exact_matches.empty?

    if currency.present?
      # Prefer match with same currency
      match = exact_matches.find { |r| r["currency"].upcase == currency.upcase }
      return match["instrument_name"] if match
    end

    # Fall back to first exact match (usually major exchange)
    exact_matches.first["instrument_name"]
  end

  private

  def search_symbol(symbol)
    uri = URI("#{BASE_URL}/symbol_search")
    uri.query = URI.encode_www_form(symbol: symbol)

    response = Net::HTTP.get_response(uri)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("TwelveData API error: #{response.code} #{response.message}")
      return []
    end

    data = JSON.parse(response.body)

    if data["status"] == "error"
      Rails.logger.warn("TwelveData API error: #{data['message']}")
      return []
    end

    data["data"] || []
  rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    Rails.logger.warn("TwelveData API error: #{e.message}")
    []
  end
end

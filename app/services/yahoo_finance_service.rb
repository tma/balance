# Service for looking up security information from Yahoo Finance API
# Used as fallback when Twelve Data doesn't have accurate data
class YahooFinanceService
  BASE_URL = "https://query1.finance.yahoo.com/v1/finance/search"

  class Error < StandardError; end

  # Exchange suffix mapping for Yahoo Finance symbols
  # IBKR exchange codes -> Yahoo Finance suffix
  EXCHANGE_SUFFIXES = {
    "LSE" => ".L",
    "LSEETF" => ".L",
    "AEB" => ".AS",      # Amsterdam
    "SBF" => ".PA",      # Paris
    "IBIS" => ".DE",     # Frankfurt/Xetra
    "VSE" => ".VI",      # Vienna
    "SWB" => ".SW",      # Swiss
    "TSE" => ".TO",      # Toronto
    "ASX" => ".AX",      # Australia
    "SEHK" => ".HK",     # Hong Kong
    "SGX" => ".SI"       # Singapore
  }.freeze

  # Look up instrument name for a symbol
  # Returns the best matching name or nil if not found
  #
  # @param symbol [String] The ticker symbol (e.g., "VWRD")
  # @param exchange [String, nil] Optional exchange to build Yahoo symbol (e.g., "LSE" -> "VWRD.L")
  # @return [String, nil] The instrument name or nil
  def self.lookup_name(symbol, exchange: nil)
    new.lookup_name(symbol, exchange: exchange)
  end

  def lookup_name(symbol, exchange: nil)
    return nil if symbol.blank?

    # Build Yahoo-style symbol with exchange suffix if we have a mapping
    yahoo_symbol = build_yahoo_symbol(symbol, exchange)

    results = search_symbol(yahoo_symbol)
    return nil if results.empty?

    # Find best match: prefer exact symbol match with longname
    match = results.find { |r| r["symbol"].upcase.start_with?(symbol.upcase) }
    return nil unless match

    # Prefer longname over shortname
    match["longname"].presence || match["shortname"]
  end

  private

  def build_yahoo_symbol(symbol, exchange)
    return symbol if exchange.blank?

    suffix = EXCHANGE_SUFFIXES[exchange.upcase]
    suffix ? "#{symbol}#{suffix}" : symbol
  end

  def search_symbol(symbol)
    uri = URI(BASE_URL)
    uri.query = URI.encode_www_form(q: symbol, quotesCount: 5)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 10

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "Mozilla/5.0 (compatible; Balance/1.0)"

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("Yahoo Finance API error: #{response.code} #{response.message}")
      return []
    end

    data = JSON.parse(response.body)
    data["quotes"] || []
  rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    Rails.logger.warn("Yahoo Finance API error: #{e.message}")
    []
  end
end

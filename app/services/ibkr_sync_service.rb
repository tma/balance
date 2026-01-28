require "net/http"
require "rexml/document"

# Interactive Brokers Flex Web Service sync implementation
class IbkrSyncService < BrokerSyncService
  BASE_URL = "https://ndcdyn.interactivebrokers.com/AccountManagement/FlexWebService"
  FLEX_VERSION = 3

  # Sync positions from IBKR Flex API and update mappings
  # Returns { positions: [...], updated_count: N, closed_count: N, errors: [...] }
  # @param sync_date [Date, nil] The date to sync data for
  def perform_sync!(sync_date: nil)
    result = { positions: [], updated_count: 0, closed_count: 0, errors: [] }
    valuation_date = sync_date || Date.current

    begin
      # Fetch positions from IBKR
      positions = fetch_positions(sync_date: sync_date)
      synced_symbols = []

      # Update or create position mappings and record valuations
      positions.each do |position_data|
        position = find_or_create_position(position_data)
        update_position(position, position_data)
        record_position_valuation!(position, position_data, date: valuation_date)
        result[:positions] << position
        synced_symbols << position_data[:symbol]
      end

      # Close positions that weren't in the sync (no longer held)
      result[:closed_count] = close_missing_positions(synced_symbols, date: valuation_date)

      # Update all assets that have mappings from this connection
      updated_assets = sync_mapped_assets
      result[:updated_count] = updated_assets.count

      # Clear error and update sync time
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

  # Test connection by fetching positions without storing anything
  # Returns { success: true, symbols: [...] } or { success: false, error: "..." }
  def test_connection
    positions = fetch_positions
    symbols = positions.map { |p| p[:symbol] }.first(5)
    { success: true, symbols: symbols, count: positions.count }
  rescue SyncError => e
    { success: false, error: e.message }
  rescue StandardError => e
    { success: false, error: "Unexpected error: #{e.message}" }
  end

  # Fetch positions from IBKR Flex API
  # @param sync_date [Date, nil] The date to fetch data for (nil = current/default)
  def fetch_positions(sync_date: nil)
    # Step 1: Request report generation
    reference_code = request_report(sync_date: sync_date)

    # Step 2: Wait briefly for report to generate
    wait(2)

    # Step 3: Fetch the generated report
    report_xml = fetch_report(reference_code)

    # Step 4: Parse positions from XML
    parse_positions(report_xml)
  end

  private

  # IBKR records valuations inline to pass through FX rates from the API
  def records_valuations_inline?
    true
  end

  # Wrapper for sleep to allow stubbing in tests
  def wait(seconds)
    sleep(seconds)
  end

  # Request report generation from IBKR
  # @param sync_date [Date, nil] The date to request data for
  def request_report(sync_date: nil)
    uri = URI("#{BASE_URL}/SendRequest")

    params = {
      t: @connection.flex_token,
      q: @connection.flex_query_id,
      v: FLEX_VERSION
    }

    # Only add date parameters for historical dates (before today)
    # IBKR returns current portfolio snapshot when no dates specified,
    # but returns end-of-day historical data when dates are specified
    if sync_date && sync_date < Date.current
      date_str = sync_date.strftime("%Y%m%d")
      params[:FromDate] = date_str
      params[:ToDate] = date_str
    end

    uri.query = URI.encode_www_form(params)

    response = make_request(uri)
    parse_send_response(response.body)
  end

  def fetch_report(reference_code, retries: 3)
    uri = URI("#{BASE_URL}/GetStatement")
    uri.query = URI.encode_www_form(
      t: @connection.flex_token,
      q: reference_code,
      v: FLEX_VERSION
    )

    retries.times do |attempt|
      response = make_request(uri)

      # Check if it's still generating
      if response.body.include?("<Status>") && response.body.include?("Fail")
        error_code = extract_error_code(response.body)
        if error_code == "1019" # Statement generation in progress
          wait(5 * (attempt + 1))
          next
        end
        handle_error_response(response.body)
      end

      return response.body
    end

    raise SyncError, "Report generation timed out after #{retries} attempts"
  end

  def make_request(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 30
    http.read_timeout = 60

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "Balance/1.0"

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise SyncError, "HTTP error: #{response.code} - #{response.message}"
    end

    response
  end

  def parse_send_response(xml_body)
    doc = REXML::Document.new(xml_body)
    status = doc.elements["//Status"]&.text

    if status == "Success"
      doc.elements["//ReferenceCode"]&.text
    else
      handle_error_response(xml_body)
    end
  end

  def extract_error_code(xml_body)
    doc = REXML::Document.new(xml_body)
    doc.elements["//ErrorCode"]&.text
  end

  def handle_error_response(xml_body)
    doc = REXML::Document.new(xml_body)
    error_code = doc.elements["//ErrorCode"]&.text
    error_message = doc.elements["//ErrorMessage"]&.text || "Unknown error"

    case error_code
    when "1012", "1015"
      raise AuthenticationError, "Authentication failed: #{error_message}"
    when "1018"
      raise RateLimitError, "Rate limited: #{error_message}"
    else
      raise SyncError, "IBKR error #{error_code}: #{error_message}"
    end
  end

  def parse_positions(xml_body)
    positions = []
    doc = REXML::Document.new(xml_body)

    # Extract account base currency from AccountInformation section
    account_base_currency = doc.elements["//AccountInformation"]&.attributes&.[]("currency")

    # IBKR Flex returns OpenPositions with OpenPosition elements
    # Filter for SUMMARY level only (excludes individual tax lots)
    doc.elements.each("//OpenPosition") do |pos|
      # Skip LOT level detail - only use SUMMARY rows which have the total position
      next if pos.attributes["levelOfDetail"] == "LOT"

      positions << {
        symbol: pos.attributes["symbol"],
        description: pos.attributes["longName"].presence || pos.attributes["description"],
        quantity: pos.attributes["position"]&.to_d,
        value: pos.attributes["positionValue"]&.to_d || pos.attributes["markValue"]&.to_d,
        currency: pos.attributes["currency"],
        exchange: pos.attributes["listingExchange"],
        fx_rate_to_base: pos.attributes["fxRateToBase"]&.to_d,
        ibkr_base_currency: account_base_currency
      }
    end

    # Parse cash balances from Cash Report (if included in Flex Query)
    doc.elements.each("//CashReportCurrency") do |cash|
      next if cash.attributes["currency"] == "BASE_SUMMARY" # Skip summary rows
      currency = cash.attributes["currency"]
      ending_cash = cash.attributes["endingCash"]&.to_d
      next if ending_cash.nil? || ending_cash.zero?

      # Cash in its own currency has fx rate of 1.0 to itself
      # Use fxRateToBase if available from cash report, otherwise it's same-currency
      fx_rate = cash.attributes["fxRateToBase"]&.to_d || (currency == account_base_currency ? 1.0 : nil)

      positions << {
        symbol: currency,
        description: "Cash (#{currency})",
        quantity: ending_cash,
        value: ending_cash,
        currency: currency,
        fx_rate_to_base: fx_rate,
        ibkr_base_currency: account_base_currency
      }
    end

    positions
  end

  def find_or_create_position(position_data)
    position = @connection.broker_positions.find_or_create_by!(symbol: position_data[:symbol]) do |p|
      p.description = position_data[:description]
      p.currency = position_data[:currency]
      p.exchange = position_data[:exchange]
    end

    # Reopen if previously closed (position reappeared)
    position.reopen! if position.closed?

    position
  end

  def update_position(position, position_data)
    position.update!(
      description: position_data[:description],
      last_quantity: position_data[:quantity],
      last_value: position_data[:value],
      currency: position_data[:currency],
      exchange: position_data[:exchange],
      last_synced_at: Time.current
    )
  end

  # Record a valuation for a position with IBKR-provided FX rate
  def record_position_valuation!(position, position_data, date:)
    return unless position_data[:value].present? && position_data[:quantity].present?

    valuation = position.position_valuations.find_or_initialize_by(date: date)
    valuation.assign_attributes(
      quantity: position_data[:quantity],
      value: position_data[:value],
      currency: position_data[:currency],
      fx_rate_to_base: position_data[:fx_rate_to_base],
      ibkr_base_currency: position_data[:ibkr_base_currency]
    )
    valuation.save!
  end

  # Close positions that weren't in the latest sync
  # Returns the count of positions closed
  def close_missing_positions(synced_symbols, date:)
    missing_positions = @connection.broker_positions.open.where.not(symbol: synced_symbols)
    count = missing_positions.count

    missing_positions.find_each { |p| p.close!(date: date) }

    count
  end
end

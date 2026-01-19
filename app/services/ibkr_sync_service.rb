require "net/http"
require "rexml/document"

# Interactive Brokers Flex Web Service sync implementation
class IbkrSyncService < BrokerSyncService
  BASE_URL = "https://ndcdyn.interactivebrokers.com/AccountManagement/FlexWebService"
  FLEX_VERSION = 3

  # Sync positions from IBKR Flex API and update mappings
  # Returns { positions: [...], updated_count: N, errors: [...] }
  def perform_sync!
    result = { positions: [], updated_count: 0, errors: [] }

    begin
      # Fetch positions from IBKR
      positions = fetch_positions

      # Update or create position mappings
      positions.each do |position_data|
        position = find_or_create_position(position_data)
        update_position(position, position_data)
        result[:positions] << position
      end

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

  # Fetch positions from IBKR Flex API
  def fetch_positions
    # Step 1: Request report generation
    reference_code = request_report

    # Step 2: Wait briefly for report to generate
    sleep(2)

    # Step 3: Fetch the generated report
    report_xml = fetch_report(reference_code)

    # Step 4: Parse positions from XML
    parse_positions(report_xml)
  end

  private

  def request_report
    uri = URI("#{BASE_URL}/SendRequest")
    uri.query = URI.encode_www_form(
      t: @connection.flex_token,
      q: @connection.flex_query_id,
      v: FLEX_VERSION
    )

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
          sleep(5 * (attempt + 1))
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

    # IBKR Flex returns OpenPositions with OpenPosition elements
    # Filter for SUMMARY level only (excludes individual tax lots)
    doc.elements.each("//OpenPosition") do |pos|
      # Skip LOT level detail - only use SUMMARY rows which have the total position
      next if pos.attributes["levelOfDetail"] == "LOT"

      positions << {
        symbol: pos.attributes["symbol"],
        description: pos.attributes["description"],
        quantity: pos.attributes["position"]&.to_d,
        value: pos.attributes["positionValue"]&.to_d || pos.attributes["markValue"]&.to_d,
        currency: pos.attributes["currency"]
      }
    end

    positions
  end

  def find_or_create_position(position_data)
    @connection.broker_positions.find_or_create_by!(symbol: position_data[:symbol]) do |p|
      p.description = position_data[:description]
      p.currency = position_data[:currency]
    end
  end

  def update_position(position, position_data)
    position.update!(
      description: position_data[:description],
      last_quantity: position_data[:quantity],
      last_value: position_data[:value],
      currency: position_data[:currency],
      last_synced_at: Time.current
    )
  end
end

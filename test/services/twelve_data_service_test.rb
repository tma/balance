require "test_helper"
require "webmock/minitest"

class TwelveDataServiceTest < ActiveSupport::TestCase
  setup do
    @api_url = "https://api.twelvedata.com/symbol_search"
  end

  test "lookup_name returns instrument name for valid symbol" do
    stub_request(:get, @api_url)
      .with(query: { symbol: "AAPL" })
      .to_return(
        status: 200,
        body: {
          data: [
            { symbol: "AAPL", instrument_name: "Apple Inc.", currency: "USD" },
            { symbol: "AAPL", instrument_name: "Apple Inc. CEDEAR", currency: "ARS" }
          ],
          status: "ok"
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = TwelveDataService.lookup_name("AAPL")
    assert_equal "Apple Inc.", result
  end

  test "lookup_name prefers matching currency" do
    stub_request(:get, @api_url)
      .with(query: { symbol: "IB01" })
      .to_return(
        status: 200,
        body: {
          data: [
            { symbol: "IB01", instrument_name: "iShares ETF (GBP)", currency: "GBP" },
            { symbol: "IB01", instrument_name: "iShares ETF (USD)", currency: "USD" }
          ],
          status: "ok"
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = TwelveDataService.lookup_name("IB01", currency: "USD")
    assert_equal "iShares ETF (USD)", result
  end

  test "lookup_name returns nil for unknown symbol" do
    stub_request(:get, @api_url)
      .with(query: { symbol: "ZZZZZ" })
      .to_return(
        status: 200,
        body: { data: [], status: "ok" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = TwelveDataService.lookup_name("ZZZZZ")
    assert_nil result
  end

  test "lookup_name returns nil for blank symbol" do
    result = TwelveDataService.lookup_name("")
    assert_nil result

    result = TwelveDataService.lookup_name(nil)
    assert_nil result
  end

  test "lookup_name handles API errors gracefully" do
    stub_request(:get, @api_url)
      .with(query: { symbol: "AAPL" })
      .to_return(status: 500, body: "Internal Server Error")

    result = TwelveDataService.lookup_name("AAPL")
    assert_nil result
  end

  test "lookup_name handles network errors gracefully" do
    stub_request(:get, @api_url)
      .with(query: { symbol: "AAPL" })
      .to_timeout

    result = TwelveDataService.lookup_name("AAPL")
    assert_nil result
  end

  test "lookup_name only matches exact symbols" do
    stub_request(:get, @api_url)
      .with(query: { symbol: "AA" })
      .to_return(
        status: 200,
        body: {
          data: [
            { symbol: "AA", instrument_name: "Alcoa Corporation", currency: "USD" },
            { symbol: "AAPL", instrument_name: "Apple Inc.", currency: "USD" }
          ],
          status: "ok"
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = TwelveDataService.lookup_name("AA")
    assert_equal "Alcoa Corporation", result
  end
end

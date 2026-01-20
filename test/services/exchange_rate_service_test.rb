require "test_helper"
require "webmock/minitest"

class ExchangeRateServiceTest < ActiveSupport::TestCase
  setup do
    WebMock.disable_net_connect!
    @base_url = "https://api.frankfurter.app"
  end

  teardown do
    WebMock.allow_net_connect!
  end

  # ========================================
  # Tests for rate() method
  # ========================================

  test "rate returns exchange rate for valid currency pair" do
    stub_request(:get, "#{@base_url}/latest")
      .with(query: { from: "USD", to: "EUR" })
      .to_return(
        status: 200,
        body: { base: "USD", date: "2026-01-20", rates: { "EUR" => 0.92 } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = ExchangeRateService.rate("USD", "EUR")
    assert_equal 0.92, result
  end

  test "rate returns 1.0 for same currency conversion" do
    # Should not make any HTTP requests
    result = ExchangeRateService.rate("USD", "USD")
    assert_equal 1.0, result
  end

  test "rate returns nil on HTTP error" do
    stub_request(:get, "#{@base_url}/latest")
      .with(query: { from: "USD", to: "EUR" })
      .to_return(status: 500, body: "Internal Server Error")

    result = ExchangeRateService.rate("USD", "EUR")
    assert_nil result
  end

  test "rate returns nil on 404 not found" do
    stub_request(:get, "#{@base_url}/latest")
      .with(query: { from: "USD", to: "XYZ" })
      .to_return(status: 404, body: { message: "not found" }.to_json)

    result = ExchangeRateService.rate("USD", "XYZ")
    assert_nil result
  end

  test "rate returns nil on malformed JSON response" do
    stub_request(:get, "#{@base_url}/latest")
      .with(query: { from: "USD", to: "EUR" })
      .to_return(
        status: 200,
        body: "this is not valid json{{{",
        headers: { "Content-Type" => "application/json" }
      )

    result = ExchangeRateService.rate("USD", "EUR")
    assert_nil result
  end

  test "rate returns nil when rates key is missing from response" do
    stub_request(:get, "#{@base_url}/latest")
      .with(query: { from: "USD", to: "EUR" })
      .to_return(
        status: 200,
        body: { base: "USD", date: "2026-01-20" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = ExchangeRateService.rate("USD", "EUR")
    assert_nil result
  end

  test "rate returns nil when target currency is missing from rates" do
    stub_request(:get, "#{@base_url}/latest")
      .with(query: { from: "USD", to: "EUR" })
      .to_return(
        status: 200,
        body: { base: "USD", date: "2026-01-20", rates: { "GBP" => 0.79 } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = ExchangeRateService.rate("USD", "EUR")
    assert_nil result
  end

  test "rate returns nil on network timeout" do
    stub_request(:get, "#{@base_url}/latest")
      .with(query: { from: "USD", to: "EUR" })
      .to_timeout

    result = ExchangeRateService.rate("USD", "EUR")
    assert_nil result
  end

  test "rate returns nil on connection refused" do
    stub_request(:get, "#{@base_url}/latest")
      .with(query: { from: "USD", to: "EUR" })
      .to_raise(Errno::ECONNREFUSED)

    result = ExchangeRateService.rate("USD", "EUR")
    assert_nil result
  end

  test "rate fetches historical rate when date is provided" do
    date = Date.new(2025, 6, 15)

    stub_request(:get, "#{@base_url}/2025-06-15")
      .with(query: { from: "USD", to: "EUR" })
      .to_return(
        status: 200,
        body: { base: "USD", date: "2025-06-15", rates: { "EUR" => 0.89 } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = ExchangeRateService.rate("USD", "EUR", date: date)
    assert_equal 0.89, result
  end

  test "rate uses latest endpoint when date is nil" do
    stub = stub_request(:get, "#{@base_url}/latest")
      .with(query: { from: "GBP", to: "JPY" })
      .to_return(
        status: 200,
        body: { base: "GBP", date: "2026-01-20", rates: { "JPY" => 190.5 } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    ExchangeRateService.rate("GBP", "JPY", date: nil)
    assert_requested(stub)
  end

  # ========================================
  # Tests for convert() method
  # ========================================

  test "convert returns converted amount" do
    stub_request(:get, "#{@base_url}/latest")
      .with(query: { from: "USD", to: "EUR" })
      .to_return(
        status: 200,
        body: { base: "USD", date: "2026-01-20", rates: { "EUR" => 0.92 } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = ExchangeRateService.convert(100, "USD", "EUR")
    assert_equal 92.0, result
  end

  test "convert rounds result to 2 decimal places" do
    stub_request(:get, "#{@base_url}/latest")
      .with(query: { from: "USD", to: "EUR" })
      .to_return(
        status: 200,
        body: { base: "USD", date: "2026-01-20", rates: { "EUR" => 0.923456 } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = ExchangeRateService.convert(100, "USD", "EUR")
    assert_equal 92.35, result
  end

  test "convert returns original amount for same currency" do
    # Should not make any HTTP requests
    result = ExchangeRateService.convert(150.75, "EUR", "EUR")
    assert_equal 150.75, result
  end

  test "convert returns nil when rate fetch fails" do
    stub_request(:get, "#{@base_url}/latest")
      .with(query: { from: "USD", to: "EUR" })
      .to_return(status: 500, body: "Server Error")

    result = ExchangeRateService.convert(100, "USD", "EUR")
    assert_nil result
  end

  test "convert returns nil when rate is nil due to missing currency in response" do
    stub_request(:get, "#{@base_url}/latest")
      .with(query: { from: "USD", to: "EUR" })
      .to_return(
        status: 200,
        body: { base: "USD", date: "2026-01-20", rates: {} }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = ExchangeRateService.convert(100, "USD", "EUR")
    assert_nil result
  end

  test "convert uses historical date when provided" do
    date = Date.new(2025, 3, 10)

    stub_request(:get, "#{@base_url}/2025-03-10")
      .with(query: { from: "EUR", to: "GBP" })
      .to_return(
        status: 200,
        body: { base: "EUR", date: "2025-03-10", rates: { "GBP" => 0.85 } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = ExchangeRateService.convert(200, "EUR", "GBP", date: date)
    assert_equal 170.0, result
  end

  test "convert handles zero amount" do
    stub_request(:get, "#{@base_url}/latest")
      .with(query: { from: "USD", to: "EUR" })
      .to_return(
        status: 200,
        body: { base: "USD", date: "2026-01-20", rates: { "EUR" => 0.92 } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = ExchangeRateService.convert(0, "USD", "EUR")
    assert_equal 0.0, result
  end

  test "convert handles negative amount" do
    stub_request(:get, "#{@base_url}/latest")
      .with(query: { from: "USD", to: "EUR" })
      .to_return(
        status: 200,
        body: { base: "USD", date: "2026-01-20", rates: { "EUR" => 0.92 } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = ExchangeRateService.convert(-100, "USD", "EUR")
    assert_equal(-92.0, result)
  end

  test "convert handles large amounts without precision loss" do
    stub_request(:get, "#{@base_url}/latest")
      .with(query: { from: "USD", to: "EUR" })
      .to_return(
        status: 200,
        body: { base: "USD", date: "2026-01-20", rates: { "EUR" => 0.92 } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = ExchangeRateService.convert(1_000_000, "USD", "EUR")
    assert_equal 920_000.0, result
  end
end

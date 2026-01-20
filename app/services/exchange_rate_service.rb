require "net/http"
require "json"

class ExchangeRateService
  # Free API from frankfurter.app (no API key required)
  BASE_URL = "https://api.frankfurter.app"

  class << self
    # Fetch exchange rate, optionally for a specific date
    # Returns nil if API fails - callers should handle nil appropriately
    # date: nil for latest rate, or a Date object for historical rate
    def rate(from_currency, to_currency, date: nil)
      return 1.0 if from_currency == to_currency

      fetch_rate(from_currency, to_currency, date)
    end

    # Convert amount between currencies
    # Returns nil if exchange rate unavailable
    def convert(amount, from_currency, to_currency, date: nil)
      return amount if from_currency == to_currency

      exchange_rate = rate(from_currency, to_currency, date: date)
      return nil if exchange_rate.nil?

      (amount * exchange_rate).round(2)
    end

    private

    def fetch_rate(from_currency, to_currency, date = nil)
      endpoint = date ? date.strftime("%Y-%m-%d") : "latest"
      uri = URI("#{BASE_URL}/#{endpoint}?from=#{from_currency}&to=#{to_currency}")

      response = Net::HTTP.get_response(uri)

      if response.is_a?(Net::HTTPSuccess)
        data = JSON.parse(response.body)
        rate = data.dig("rates", to_currency)

        if rate.nil?
          Rails.logger.error "Exchange rate API returned unexpected format: missing rates[#{to_currency}] in #{data.inspect}"
          return nil
        end

        rate
      else
        Rails.logger.error "Exchange rate API error: #{response.code} - #{response.body}"
        nil
      end
    rescue StandardError => e
      Rails.logger.error "Exchange rate fetch failed: #{e.message}"
      nil
    end
  end
end

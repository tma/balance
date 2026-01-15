require "net/http"
require "json"

class ExchangeRateService
  # Free API from frankfurter.app (no API key required)
  BASE_URL = "https://api.frankfurter.app"

  class << self
    def rate(from_currency, to_currency)
      return 1.0 if from_currency == to_currency

      fetch_rate(from_currency, to_currency)
    end

    def convert(amount, from_currency, to_currency)
      return amount if from_currency == to_currency

      exchange_rate = rate(from_currency, to_currency)
      (amount * exchange_rate).round(2)
    end

    private

    def fetch_rate(from_currency, to_currency)
      uri = URI("#{BASE_URL}/latest?from=#{from_currency}&to=#{to_currency}")

      response = Net::HTTP.get_response(uri)

      if response.is_a?(Net::HTTPSuccess)
        data = JSON.parse(response.body)
        data["rates"][to_currency]
      else
        Rails.logger.error "Exchange rate API error: #{response.code} - #{response.body}"
        # Fallback: return 1.0 if API fails (will use original value)
        1.0
      end
    rescue StandardError => e
      Rails.logger.error "Exchange rate fetch failed: #{e.message}"
      1.0
    end
  end
end

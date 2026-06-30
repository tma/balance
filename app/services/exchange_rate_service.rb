require "net/http"
require "json"

class ExchangeRateService
  # Free API from Frankfurter (no API key required)
  BASE_URL = "https://api.frankfurter.dev/v1"

  class << self
    # Fetch exchange rate for a specific date
    # Returns nil if API fails - callers should handle nil appropriately
    # date: Date object for historical rate (required)
    def rate(from_currency, to_currency, date:)
      return 1.0 if from_currency == to_currency

      fetch_rate(from_currency, to_currency, date)
    end

    # Convert amount between currencies
    # Returns nil if exchange rate unavailable
    def convert(amount, from_currency, to_currency, date:)
      return amount if from_currency == to_currency

      exchange_rate = rate(from_currency, to_currency, date: date)
      return nil if exchange_rate.nil?

      (amount * exchange_rate).round(2)
    end

    private

    def fetch_rate(from_currency, to_currency, date)
      endpoint = date.strftime("%Y-%m-%d")
      uri = URI("#{BASE_URL}/#{endpoint}?from=#{from_currency}&to=#{to_currency}")

      response = get_response(uri)

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

    def get_response(uri, limit: 3)
      raise "too many redirects" if limit <= 0

      response = Net::HTTP.get_response(uri)
      if response.is_a?(Net::HTTPRedirection)
        location = response["location"]
        raise "redirect missing location" if location.blank?

        redirected_uri = URI(location)
        raise "unsafe redirect scheme: #{redirected_uri.scheme}" unless redirected_uri.is_a?(URI::HTTPS)

        return get_response(redirected_uri, limit: limit - 1)
      end

      response
    end
  end
end

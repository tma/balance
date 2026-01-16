require "httparty"

class OllamaService
  class Error < StandardError; end
  class TimeoutError < Error; end
  class UnavailableError < Error; end
  class ParseError < Error; end

  class << self
    # Generate a response from Ollama
    # @param prompt [String] The prompt to send
    # @param format [String, nil] Optional format (e.g., "json")
    # @return [String] The generated response
    def generate(prompt, format: nil)
      raise UnavailableError, "Ollama is not available" unless available?

      body = {
        model: config.model,
        prompt: prompt,
        stream: false
      }
      body[:format] = format if format

      response = HTTParty.post(
        "#{config.host}/api/generate",
        body: body.to_json,
        headers: { "Content-Type" => "application/json" },
        open_timeout: 30,
        read_timeout: config.timeout
      )

      if response.success?
        response.parsed_response["response"]
      else
        raise Error, "Ollama API error: #{response.code} - #{response.body}"
      end
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise TimeoutError, "Ollama request timed out: #{e.message}"
    rescue Errno::ECONNREFUSED => e
      raise UnavailableError, "Cannot connect to Ollama: #{e.message}"
    end

    # Generate a JSON response from Ollama
    # @param prompt [String] The prompt to send
    # @return [Hash] The parsed JSON response
    def generate_json(prompt)
      response = generate(prompt, format: "json")
      JSON.parse(response)
    rescue JSON::ParserError => e
      raise ParseError, "Failed to parse Ollama response as JSON: #{e.message}"
    end

    # Check if Ollama is available and responding
    # @return [Boolean]
    def available?
      response = HTTParty.get(
        "#{config.host}/api/tags",
        timeout: 5
      )
      response.success?
    rescue StandardError
      false
    end

    # Check if the configured model is available
    # @return [Boolean]
    def model_available?
      return false unless available?

      response = HTTParty.get(
        "#{config.host}/api/tags",
        timeout: 5
      )

      return false unless response.success?

      models = response.parsed_response["models"] || []
      models.any? { |m| m["name"]&.start_with?(config.model) }
    rescue StandardError
      false
    end

    # Pull the configured model
    # @return [Boolean] true if successful
    def pull_model
      response = HTTParty.post(
        "#{config.host}/api/pull",
        body: { name: config.model }.to_json,
        headers: { "Content-Type" => "application/json" },
        timeout: 600 # Model downloads can take a while
      )
      response.success?
    rescue StandardError
      false
    end

    private

    def config
      Rails.application.config.ollama
    end
  end
end

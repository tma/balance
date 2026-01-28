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
      parse_json_response(response)
    end

    # Generate an embedding vector for text
    # @param text [String] The text to embed
    # @return [Array<Float>] The embedding vector
    def embed(text)
      raise UnavailableError, "Ollama is not available" unless available?

      response = HTTParty.post(
        "#{config.host}/api/embeddings",
        body: { model: config.embedding_model, prompt: text }.to_json,
        headers: { "Content-Type" => "application/json" },
        timeout: 30
      )

      if response.success?
        response.parsed_response["embedding"]
      else
        raise Error, "Ollama embedding error: #{response.code} - #{response.body}"
      end
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise TimeoutError, "Ollama embedding request timed out: #{e.message}"
    rescue Errno::ECONNREFUSED => e
      raise UnavailableError, "Cannot connect to Ollama: #{e.message}"
    end

    # Attempt to parse JSON, with repair for truncated responses
    # @param response [String] The JSON string to parse
    # @return [Hash, Array] The parsed JSON
    def parse_json_response(response)
      JSON.parse(response)
    rescue JSON::ParserError => e
      # Try to repair truncated JSON
      repaired = repair_truncated_json(response)
      begin
        JSON.parse(repaired)
      rescue JSON::ParserError
        # Log the original response for debugging
        Rails.logger.error "Failed to parse Ollama JSON response: #{response.truncate(500)}"
        raise ParseError, "Failed to parse Ollama response as JSON: #{e.message}"
      end
    end

    # Attempt to repair truncated JSON by closing open brackets/braces
    # @param json_str [String] The potentially truncated JSON
    # @return [String] The repaired JSON string
    def repair_truncated_json(json_str)
      return json_str if json_str.blank?

      # Track open brackets and braces
      stack = []
      in_string = false
      escape_next = false

      json_str.each_char do |char|
        if escape_next
          escape_next = false
          next
        end

        case char
        when "\\"
          escape_next = true if in_string
        when '"'
          in_string = !in_string unless escape_next
        when "{", "["
          stack.push(char) unless in_string
        when "}"
          stack.pop if !in_string && stack.last == "{"
        when "]"
          stack.pop if !in_string && stack.last == "["
        end
      end

      # Close any remaining open structures
      repaired = json_str.dup

      # If we're in a string, close it
      if in_string
        repaired += '"'
      end

      # Close remaining brackets/braces in reverse order
      stack.reverse_each do |open_char|
        repaired += (open_char == "{" ? "}" : "]")
      end

      repaired
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

    # Check if the configured embedding model is available
    # @return [Boolean]
    def embedding_model_available?
      return false unless available?

      response = HTTParty.get(
        "#{config.host}/api/tags",
        timeout: 5
      )

      return false unless response.success?

      models = response.parsed_response["models"] || []
      models.any? { |m| m["name"]&.start_with?(config.embedding_model) }
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

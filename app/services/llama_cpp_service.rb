class LlamaCppService
  Error = LlmService::Error
  TimeoutError = LlmService::TimeoutError
  UnavailableError = LlmService::UnavailableError
  ParseError = LlmService::ParseError

  class << self
    def generate(prompt, format: nil)
      raise UnavailableError, "llama-server is not available" unless available?

      body = {
        model: config.model,
        messages: [ { role: "user", content: prompt } ],
        stream: false
      }
      response_format = response_format_for(format)
      body[:response_format] = response_format if response_format

      response = HTTParty.post(
        "#{config.host}/v1/chat/completions",
        body: body.to_json,
        headers: { "Content-Type" => "application/json" },
        open_timeout: 30,
        read_timeout: config.timeout
      )

      if response.success?
        response.parsed_response.dig("choices", 0, "message", "content")
      else
        raise Error, "llama-server API error: #{response.code} - #{response.body}"
      end
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise TimeoutError, "llama-server request timed out: #{e.message}"
    rescue Errno::ECONNREFUSED => e
      raise UnavailableError, "Cannot connect to llama-server: #{e.message}"
    end

    def generate_json(prompt, schema: nil)
      LlmService.parse_json_response(generate(prompt, format: schema || "json"))
    end

    def embed(text)
      raise UnavailableError, "llama-server is not available" unless available?

      response = HTTParty.post(
        "#{config.host}/v1/embeddings",
        body: { model: config.embedding_model, input: text }.to_json,
        headers: { "Content-Type" => "application/json" },
        timeout: 30
      )

      if response.success?
        response.parsed_response.dig("data", 0, "embedding")
      else
        raise Error, "llama-server embedding error: #{response.code} - #{response.body}"
      end
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise TimeoutError, "llama-server embedding request timed out: #{e.message}"
    rescue Errno::ECONNREFUSED => e
      raise UnavailableError, "Cannot connect to llama-server: #{e.message}"
    end

    def available?
      response = HTTParty.get("#{config.host}/v1/models", timeout: 5)
      response.success?
    rescue StandardError
      false
    end

    def model_available?
      listed_model?(config.model)
    end

    def embedding_model_available?
      listed_model?(config.embedding_model)
    end

    def pull_model
      false
    end

    private

    def config
      Rails.application.config.ollama
    end

    def response_format_for(format)
      case format
      when Hash
        { type: "json_schema", json_schema: { name: "response", schema: format } }
      when "json"
        { type: "json_object" }
      end
    end

    def listed_model?(name)
      return false unless available?

      response = HTTParty.get("#{config.host}/v1/models", timeout: 5)
      return false unless response.success?

      models = response.parsed_response["data"] || []
      models.any? { |model| model["id"] == name || model["id"]&.start_with?("#{name}:") }
    rescue StandardError
      false
    end
  end
end

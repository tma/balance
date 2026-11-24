class OllamaService
  Error = LlmService::Error
  TimeoutError = LlmService::TimeoutError
  UnavailableError = LlmService::UnavailableError
  ParseError = LlmService::ParseError

  class << self
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

    def generate_json(prompt, schema: nil)
      LlmService.parse_json_response(generate(prompt, format: schema || "json"))
    end

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

    def available?
      response = HTTParty.get("#{config.host}/api/tags", timeout: 5)
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
      response = HTTParty.post(
        "#{config.host}/api/pull",
        body: { name: config.model }.to_json,
        headers: { "Content-Type" => "application/json" },
        timeout: 600
      )
      response.success?
    rescue StandardError
      false
    end

    private

    def config
      Rails.application.config.ollama
    end

    def listed_model?(name)
      return false unless available?

      response = HTTParty.get("#{config.host}/api/tags", timeout: 5)
      return false unless response.success?

      models = response.parsed_response["models"] || []
      models.any? { |model| model["name"]&.start_with?(name) }
    rescue StandardError
      false
    end
  end
end

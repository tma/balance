class LlmService
  class Error < StandardError; end
  class TimeoutError < Error; end
  class UnavailableError < Error; end
  class ParseError < Error; end

  class << self
    def generate(...) = client.generate(...)
    def generate_json(...) = client.generate_json(...)
    def embed(...) = client.embed(...)
    def available? = client.available?
    def model_available? = client.model_available?
    def embedding_model_available? = client.embedding_model_available?
    def pull_model = client.pull_model

    def client
      case Rails.application.config.llm_backend
      when "ollama" then OllamaService
      when "llama_cpp" then LlamaCppService
      else
        raise ArgumentError, "LLM_BACKEND must be ollama or llama_cpp"
      end
    end

    def parse_json_response(response)
      JSON.parse(response)
    rescue JSON::ParserError => e
      repaired = repair_truncated_json(response)
      begin
        JSON.parse(repaired)
      rescue JSON::ParserError
        Rails.logger.error "Failed to parse LLM JSON response: #{response.to_s.truncate(500)}"
        raise ParseError, "Failed to parse LLM response as JSON: #{e.message}"
      end
    end

    def repair_truncated_json(json_str)
      return json_str if json_str.blank?

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

      repaired = json_str.dup
      repaired += '"' if in_string
      stack.reverse_each { |open_char| repaired += (open_char == "{" ? "}" : "]") }
      repaired
    end
  end
end

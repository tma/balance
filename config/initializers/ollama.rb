# Ollama LLM configuration for transaction import
Rails.application.config.ollama = ActiveSupport::OrderedOptions.new.tap do |config|
  config.host = ENV.fetch("OLLAMA_HOST", "http://localhost:11434")
  config.model = ENV.fetch("OLLAMA_MODEL", "mistral")
  config.timeout = ENV.fetch("OLLAMA_TIMEOUT", 120).to_i
end

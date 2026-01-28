# Ollama LLM configuration for transaction import
Rails.application.config.ollama = ActiveSupport::OrderedOptions.new.tap do |config|
  config.host = ENV.fetch("OLLAMA_HOST", "http://localhost:11434")
  config.model = ENV.fetch("OLLAMA_MODEL", "llama3.1:8b")
  # Timeout in seconds per chunk - large pages may need 5+ minutes
  config.timeout = ENV.fetch("OLLAMA_TIMEOUT", 600).to_i
  # Embedding model for category matching
  config.embedding_model = ENV.fetch("OLLAMA_EMBEDDING_MODEL", "nomic-embed-text")
  # Confidence threshold for embedding-based categorization (0.0 - 1.0)
  config.embedding_confidence_threshold = ENV.fetch("OLLAMA_EMBEDDING_CONFIDENCE", 0.85).to_f
end

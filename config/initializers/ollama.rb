# Ollama LLM configuration for transaction import
Rails.application.config.ollama = ActiveSupport::OrderedOptions.new.tap do |config|
  config.host = ENV.fetch("OLLAMA_HOST", "http://localhost:11434")
  config.model = ENV.fetch("OLLAMA_MODEL", "llama3.1:8b")
  # Timeout in seconds per chunk - large pages may need 5+ minutes
  config.timeout = ENV.fetch("OLLAMA_TIMEOUT", 600).to_i
  # Embedding model for category matching
  # mxbai-embed-large (335M, 1024 dims) — best accuracy on short transaction descriptions.
  # nomic-embed-text (137M, 768 dims) produces degenerate/identical vectors for short uppercase
  # text, making it unsuitable for transaction categorization.
  config.embedding_model = ENV.fetch("OLLAMA_EMBEDDING_MODEL", "mxbai-embed-large")
  # Confidence threshold for embedding-based categorization (0.0 - 1.0)
  # mxbai-embed-large same-category scores typically 0.55-0.78, so 0.75 catches only
  # high-confidence matches and lets ambiguous cases fall through to LLM (Phase 3).
  config.embedding_confidence_threshold = ENV.fetch("OLLAMA_EMBEDDING_CONFIDENCE", 0.75).to_f
end

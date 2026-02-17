# Background job to compute and store embedding for a category
# Triggered automatically when category name changes
class CategoryEmbeddingJob < ApplicationJob
  queue_as :default

  # Retry with exponential backoff if Ollama is temporarily unavailable
  retry_on OllamaService::UnavailableError, wait: :polynomially_longer, attempts: 3
  retry_on OllamaService::TimeoutError, wait: 30.seconds, attempts: 3

  # Discard if category no longer exists
  discard_on ActiveRecord::RecordNotFound

  def perform(category_id)
    category = Category.find(category_id)

    unless OllamaService.embedding_model_available?
      Rails.logger.warn "CategoryEmbeddingJob: Embedding model not available, skipping category #{category_id}"
      return
    end

    Rails.logger.info "CategoryEmbeddingJob: Computing embedding for '#{category.name}'"

    vector = OllamaService.embed(category.embedding_text)
    category.update_column(:embedding, vector.pack("f*"))

    Rails.logger.info "CategoryEmbeddingJob: Embedding stored for '#{category.name}' (#{vector.size} dimensions)"
  rescue OllamaService::Error => e
    Rails.logger.error "CategoryEmbeddingJob: Failed to compute embedding for category #{category_id}: #{e.message}"
    raise # Re-raise to trigger retry
  end
end

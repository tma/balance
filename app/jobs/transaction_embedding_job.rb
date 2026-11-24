class TransactionEmbeddingJob < ApplicationJob
  queue_as :default

  retry_on LlmService::UnavailableError, wait: :polynomially_longer, attempts: 3
  retry_on LlmService::TimeoutError, wait: 30.seconds, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(transaction_id)
    transaction = Transaction.find(transaction_id)

    unless LlmService.embedding_model_available?
      Rails.logger.warn "TransactionEmbeddingJob: Embedding model not available, skipping"
      return
    end

    return if transaction.embedding.present? # Already embedded

    vector = LlmService.embed(transaction.description)
    transaction.update_column(:embedding, vector.pack("f*"))
  end
end

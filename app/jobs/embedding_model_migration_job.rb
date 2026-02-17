class EmbeddingModelMigrationJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "EmbeddingModelMigration: clearing all embeddings..."

    # Clear transaction embeddings
    txn_count = Transaction.where.not(embedding: nil).count
    Transaction.where.not(embedding: nil).update_all(embedding: nil)
    Rails.logger.info "EmbeddingModelMigration: cleared #{txn_count} transaction embeddings"

    # Clear category embeddings
    cat_count = Category.where.not(embedding: nil).count
    Category.where.not(embedding: nil).update_all(embedding: nil)
    Rails.logger.info "EmbeddingModelMigration: cleared #{cat_count} category embeddings"

    # Clear machine patterns (they were derived from old embeddings/LLM context)
    pattern_count = CategoryPattern.machine.count
    CategoryPattern.machine.delete_all
    Rails.logger.info "EmbeddingModelMigration: cleared #{pattern_count} machine patterns"

    # Re-enqueue embedding jobs for everything
    Transaction.find_each { |t| TransactionEmbeddingJob.perform_later(t.id) }
    Category.find_each { |c| CategoryEmbeddingJob.perform_later(c.id) }

    Rails.logger.info "EmbeddingModelMigration: enqueued re-embedding for " \
                      "#{txn_count} transactions and #{cat_count} categories"
  end
end

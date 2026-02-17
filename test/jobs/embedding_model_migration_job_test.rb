require "test_helper"

class EmbeddingModelMigrationJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @groceries = categories(:groceries)
    @transaction = transactions(:grocery_shopping)

    # Set up embeddings
    embedding = Array.new(768) { 0.5 }
    @groceries.update_column(:embedding, embedding.pack("f*"))
    @transaction.update_column(:embedding, embedding.pack("f*"))
  end

  test "clears all transaction embeddings" do
    assert_not_nil @transaction.reload.embedding

    perform_enqueued_jobs(only: EmbeddingModelMigrationJob) do
      EmbeddingModelMigrationJob.perform_now
    end

    assert_nil @transaction.reload.embedding
  end

  test "clears all category embeddings" do
    assert_not_nil @groceries.reload.embedding

    perform_enqueued_jobs(only: EmbeddingModelMigrationJob) do
      EmbeddingModelMigrationJob.perform_now
    end

    assert_nil @groceries.reload.embedding
  end

  test "clears machine patterns" do
    assert CategoryPattern.machine.exists?

    perform_enqueued_jobs(only: EmbeddingModelMigrationJob) do
      EmbeddingModelMigrationJob.perform_now
    end

    assert_equal 0, CategoryPattern.machine.count
  end

  test "preserves human patterns" do
    human_count = CategoryPattern.human.count
    assert human_count > 0

    perform_enqueued_jobs(only: EmbeddingModelMigrationJob) do
      EmbeddingModelMigrationJob.perform_now
    end

    assert_equal human_count, CategoryPattern.human.count
  end

  test "enqueues TransactionEmbeddingJob for all transactions" do
    EmbeddingModelMigrationJob.perform_now

    assert_enqueued_jobs Transaction.count, only: TransactionEmbeddingJob
  end

  test "enqueues CategoryEmbeddingJob for all categories" do
    EmbeddingModelMigrationJob.perform_now

    assert_enqueued_jobs Category.count, only: CategoryEmbeddingJob
  end
end

require "test_helper"

class TransactionEmbeddingJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    WebMock.disable_net_connect!
    @transaction = transactions(:grocery_shopping)
    @ollama_host = Rails.application.config.ollama.host
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "embeds transaction description" do
    @transaction.update_column(:embedding, nil)
    embedding = Array.new(768) { |i| i * 0.001 }

    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [ { name: "#{Rails.application.config.ollama.embedding_model}:latest" } ] }.to_json,
                 headers: { "Content-Type" => "application/json" })

    stub_request(:post, "#{@ollama_host}/api/embeddings")
      .to_return(status: 200, body: { embedding: embedding }.to_json,
                 headers: { "Content-Type" => "application/json" })

    TransactionEmbeddingJob.perform_now(@transaction.id)

    @transaction.reload
    assert_not_nil @transaction.embedding
    vector = @transaction.embedding_vector
    assert_equal 768, vector.size
  end

  test "skips if transaction already has embedding" do
    embedding = Array.new(768) { 0.5 }
    @transaction.update_column(:embedding, embedding.pack("f*"))

    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [ { name: "#{Rails.application.config.ollama.embedding_model}:latest" } ] }.to_json,
                 headers: { "Content-Type" => "application/json" })

    # Should not call embeddings API
    TransactionEmbeddingJob.perform_now(@transaction.id)

    assert_not_requested(:post, "#{@ollama_host}/api/embeddings")
  end

  test "skips if embedding model is unavailable" do
    @transaction.update_column(:embedding, nil)

    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [] }.to_json,
                 headers: { "Content-Type" => "application/json" })

    TransactionEmbeddingJob.perform_now(@transaction.id)

    @transaction.reload
    assert_nil @transaction.embedding
  end

  test "discards job when transaction not found" do
    assert_nothing_raised do
      TransactionEmbeddingJob.perform_now(-1)
    end
  end
end

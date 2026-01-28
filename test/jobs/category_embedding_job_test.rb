require "test_helper"

class CategoryEmbeddingJobTest < ActiveJob::TestCase
  setup do
    WebMock.disable_net_connect!
    @category = categories(:groceries)
    @ollama_host = Rails.application.config.ollama.host
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "computes and stores embedding for category" do
    mock_vector = Array.new(768) { |i| i * 0.001 }

    # Stub Ollama to return embedding model available
    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [ { name: "nomic-embed-text:latest" } ] }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:post, "#{@ollama_host}/api/embeddings")
      .to_return(status: 200, body: { embedding: mock_vector }.to_json, headers: { "Content-Type" => "application/json" })

    CategoryEmbeddingJob.perform_now(@category.id)

    @category.reload
    assert_not_nil @category.embedding
    assert_equal 768, @category.embedding_vector.size
  end

  test "skips when embedding model unavailable" do
    @category.update_column(:embedding, nil)

    # Stub Ollama to return no embedding model
    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [] }.to_json, headers: { "Content-Type" => "application/json" })

    CategoryEmbeddingJob.perform_now(@category.id)

    @category.reload
    assert_nil @category.embedding
  end

  test "discards job when category not found" do
    assert_nothing_raised do
      CategoryEmbeddingJob.perform_now(-1)
    end
  end

  test "uses category embedding_text for embedding" do
    @category.update!(match_patterns: "test pattern")
    expected_text = @category.embedding_text

    # Stub Ollama to return embedding model available
    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [ { name: "nomic-embed-text:latest" } ] }.to_json, headers: { "Content-Type" => "application/json" })

    # Capture the request to verify embedding_text is used
    embedding_request = stub_request(:post, "#{@ollama_host}/api/embeddings")
      .with { |request| JSON.parse(request.body)["prompt"] == expected_text }
      .to_return(status: 200, body: { embedding: Array.new(768) { 0.0 } }.to_json, headers: { "Content-Type" => "application/json" })

    CategoryEmbeddingJob.perform_now(@category.id)

    assert_requested embedding_request
  end
end

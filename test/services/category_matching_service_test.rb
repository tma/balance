require "test_helper"

class CategoryMatchingServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    # Disable real network connections for these tests
    WebMock.disable_net_connect!

    @groceries = categories(:groceries)
    # Ensure human patterns exist via CategoryPattern (fixtures already have these)
    CategoryPattern.find_or_create_by!(category: @groceries, pattern: "Whole Foods", source: "human")
    CategoryPattern.find_or_create_by!(category: @groceries, pattern: "Trader Joe", source: "human")

    @salary = categories(:salary)

    # Set up embeddings for testing
    @groceries_embedding = Array.new(768) { |i| i * 0.001 }
    @salary_embedding = Array.new(768) { |i| i * 0.002 }
    @groceries.update_column(:embedding, @groceries_embedding.pack("f*"))
    @salary.update_column(:embedding, @salary_embedding.pack("f*"))

    @ollama_host = Rails.application.config.ollama.host
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "categorize does nothing for empty transactions" do
    service = CategoryMatchingService.new([])
    service.categorize
    assert true # Just verify no errors
  end

  test "categorize skips all categorization when embedding model unavailable" do
    transactions = [
      { description: "Whole Foods Market", transaction_type: "expense", amount: 50.0 }
    ]

    # Stub Ollama to return no models
    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [] }.to_json, headers: { "Content-Type" => "application/json" })

    service = CategoryMatchingService.new(transactions)
    service.categorize

    assert_nil transactions.first[:category_id]
  end

  test "phase 1 categorizes by pattern matching" do
    transactions = [
      { description: "WHOLE FOODS MARKET #123", transaction_type: "expense", amount: 50.0 }
    ]

    # Stub Ollama to return embedding model available
    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [ { name: "#{Rails.application.config.ollama.embedding_model}:latest" } ] }.to_json, headers: { "Content-Type" => "application/json" })

    service = CategoryMatchingService.new(transactions)
    service.categorize

    assert_equal @groceries.id, transactions.first[:category_id]
    assert_equal @groceries.name, transactions.first[:category_name]
  end

  test "phase 2 categorizes by embedding when pattern fails and confidence is high" do
    transactions = [
      { description: "Random grocery store", transaction_type: "expense", amount: 50.0 }
    ]

    # Stub Ollama to return embedding model available
    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [ { name: "#{Rails.application.config.ollama.embedding_model}:latest" } ] }.to_json, headers: { "Content-Type" => "application/json" })

    # Return embedding identical to groceries (similarity = 1.0)
    stub_request(:post, "#{@ollama_host}/api/embeddings")
      .to_return(status: 200, body: { embedding: @groceries_embedding }.to_json, headers: { "Content-Type" => "application/json" })

    service = CategoryMatchingService.new(transactions)
    service.categorize

    # Should match groceries due to identical embedding
    assert_equal @groceries.id, transactions.first[:category_id]
  end

  test "phase 3 falls back to LLM when embedding confidence is low" do
    transactions = [
      { description: "Ambiguous purchase", transaction_type: "expense", amount: 50.0 }
    ]

    # Stub Ollama to return embedding model available
    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [ { name: "#{Rails.application.config.ollama.embedding_model}:latest" } ] }.to_json, headers: { "Content-Type" => "application/json" })

    # Return very different embedding (orthogonal - low similarity)
    orthogonal_vector = Array.new(768) { |i| (i % 2 == 0) ? 1.0 : -1.0 }
    stub_request(:post, "#{@ollama_host}/api/embeddings")
      .to_return(status: 200, body: { embedding: orthogonal_vector }.to_json, headers: { "Content-Type" => "application/json" })

    # Stub LLM to return groceries category
    stub_request(:post, "#{@ollama_host}/api/generate")
      .to_return(status: 200, body: { response: { category: @groceries.name }.to_json }.to_json, headers: { "Content-Type" => "application/json" })

    service = CategoryMatchingService.new(transactions)
    service.categorize

    assert_equal @groceries.id, transactions.first[:category_id]
  end

  test "handles OllamaService errors gracefully" do
    transactions = [
      { description: "Test transaction", transaction_type: "expense", amount: 50.0 }
    ]

    # Stub Ollama model check to succeed but embeddings to fail
    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [ { name: "#{Rails.application.config.ollama.embedding_model}:latest" } ] }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:post, "#{@ollama_host}/api/embeddings")
      .to_return(status: 500, body: "Internal Server Error")

    service = CategoryMatchingService.new(transactions)
    service.categorize

    # Should not raise, but transaction remains uncategorized
    assert_nil transactions.first[:category_id]
  end

  test "reports progress during categorization" do
    transactions = [
      { description: "WHOLE FOODS #1", transaction_type: "expense", amount: 10.0 },
      { description: "TRADER JOE #2", transaction_type: "expense", amount: 20.0 }
    ]

    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [ { name: "#{Rails.application.config.ollama.embedding_model}:latest" } ] }.to_json, headers: { "Content-Type" => "application/json" })

    progress_reports = []
    progress_callback = ->(current, total, message:) { progress_reports << { current: current, total: total } }

    service = CategoryMatchingService.new(transactions, on_progress: progress_callback)
    service.categorize

    assert_equal 2, progress_reports.size
    assert_equal({ current: 1, total: 2 }, progress_reports[0])
    assert_equal({ current: 2, total: 2 }, progress_reports[1])
  end

  test "cosine_similarity returns correct values" do
    service = CategoryMatchingService.new([])

    # Identical vectors should have similarity of 1.0
    vec = [ 1.0, 0.0, 0.0 ]
    similarity = service.send(:cosine_similarity, vec, vec)
    assert_in_delta 1.0, similarity, 0.0001

    # Orthogonal vectors should have similarity of 0.0
    vec_a = [ 1.0, 0.0, 0.0 ]
    vec_b = [ 0.0, 1.0, 0.0 ]
    similarity = service.send(:cosine_similarity, vec_a, vec_b)
    assert_in_delta 0.0, similarity, 0.0001

    # Opposite vectors should have similarity of -1.0
    vec_a = [ 1.0, 0.0, 0.0 ]
    vec_b = [ -1.0, 0.0, 0.0 ]
    similarity = service.send(:cosine_similarity, vec_a, vec_b)
    assert_in_delta(-1.0, similarity, 0.0001)
  end

  test "cosine_similarity handles nil vectors" do
    service = CategoryMatchingService.new([])

    assert_equal 0.0, service.send(:cosine_similarity, nil, [ 1.0, 2.0 ])
    assert_equal 0.0, service.send(:cosine_similarity, [ 1.0, 2.0 ], nil)
    assert_equal 0.0, service.send(:cosine_similarity, nil, nil)
  end

  test "cosine_similarity handles empty vectors" do
    service = CategoryMatchingService.new([])

    assert_equal 0.0, service.send(:cosine_similarity, [], [ 1.0, 2.0 ])
    assert_equal 0.0, service.send(:cosine_similarity, [ 1.0, 2.0 ], [])
  end
end

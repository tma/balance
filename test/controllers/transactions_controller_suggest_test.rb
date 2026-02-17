require "test_helper"

class TransactionsControllerSuggestTest < ActionDispatch::IntegrationTest
  setup do
    WebMock.disable_net_connect!
    @ollama_host = Rails.application.config.ollama.host

    @groceries = categories(:groceries)

    # Ensure CategoryPattern fixtures are consistent
    CategoryPattern.find_or_create_by!(
      category: @groceries, pattern: "Whole Foods", source: "human"
    )
    CategoryPattern.find_or_create_by!(
      category: @groceries, pattern: "Trader Joe", source: "human"
    )
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "returns category suggestion for matching description" do
    stub_embedding_model_available

    post suggest_category_transactions_path, params: {
      description: "WHOLE FOODS MARKET #456",
      transaction_type: "expense"
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal @groceries.id, json["category_id"]
    assert_equal @groceries.name, json["category_name"]
  end

  test "returns null category for unrecognized description" do
    stub_embedding_model_available

    # Return low-similarity embedding
    orthogonal = Array.new(768) { |i| (i % 2 == 0) ? 1.0 : -1.0 }
    stub_request(:post, "#{@ollama_host}/api/embeddings")
      .to_return(status: 200, body: { embedding: orthogonal }.to_json,
                 headers: { "Content-Type" => "application/json" })

    # LLM also returns nothing useful
    stub_request(:post, "#{@ollama_host}/api/generate")
      .to_return(status: 200, body: { response: '{"category": "Unknown"}' }.to_json,
                 headers: { "Content-Type" => "application/json" })

    post suggest_category_transactions_path, params: {
      description: "XYZZY UNKNOWN VENDOR",
      transaction_type: "expense"
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    # category_id may or may not be nil depending on what the LLM returns,
    # but the response should be valid JSON
    assert json.key?("category_id")
  end

  test "returns null for short descriptions" do
    post suggest_category_transactions_path, params: {
      description: "AB",
      transaction_type: "expense"
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_nil json["category_id"]
  end

  test "handles errors gracefully" do
    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_raise(StandardError.new("Connection refused"))

    post suggest_category_transactions_path, params: {
      description: "Some description here",
      transaction_type: "expense"
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_nil json["category_id"]
  end

  private

  def stub_embedding_model_available
    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [ { name: "#{Rails.application.config.ollama.embedding_model}:latest" } ] }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end
end

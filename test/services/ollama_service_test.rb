require "test_helper"

class OllamaServiceTest < ActiveSupport::TestCase
  setup do
    WebMock.disable_net_connect!
    @ollama_host = Rails.application.config.ollama.host
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "config uses environment variables with defaults" do
    config = Rails.application.config.ollama

    assert_respond_to config, :host
    assert_respond_to config, :model
    assert_respond_to config, :timeout
    assert_respond_to config, :embedding_model
    assert_respond_to config, :embedding_confidence_threshold

    # Check defaults are set
    assert_not_nil config.host
    assert_not_nil config.model
    assert_kind_of Integer, config.timeout
    assert_equal "mxbai-embed-large", config.embedding_model
    assert_equal 0.75, config.embedding_confidence_threshold
  end

  test "available? returns true when Ollama responds" do
    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [] }.to_json, headers: { "Content-Type" => "application/json" })

    assert OllamaService.available?
  end

  test "available? returns false when Ollama is unreachable" do
    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_timeout

    assert_not OllamaService.available?
  end

  test "model_available? returns true when model is present" do
    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [ { name: "llama3.1:8b" } ] }.to_json, headers: { "Content-Type" => "application/json" })

    assert OllamaService.model_available?
  end

  test "model_available? returns false when model is missing" do
    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [ { name: "other-model" } ] }.to_json, headers: { "Content-Type" => "application/json" })

    assert_not OllamaService.model_available?
  end

  test "embedding_model_available? returns true when embedding model is present" do
    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [ { name: "#{Rails.application.config.ollama.embedding_model}:latest" } ] }.to_json, headers: { "Content-Type" => "application/json" })

    assert OllamaService.embedding_model_available?
  end

  test "embedding_model_available? returns false when embedding model is missing" do
    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [ { name: "llama3.1:8b" } ] }.to_json, headers: { "Content-Type" => "application/json" })

    assert_not OllamaService.embedding_model_available?
  end

  test "error classes are defined" do
    assert_kind_of Class, OllamaService::Error
    assert_kind_of Class, OllamaService::TimeoutError
    assert_kind_of Class, OllamaService::UnavailableError
    assert_kind_of Class, OllamaService::ParseError

    # Check inheritance
    assert OllamaService::TimeoutError < OllamaService::Error
    assert OllamaService::UnavailableError < OllamaService::Error
    assert OllamaService::ParseError < OllamaService::Error
  end

  test "embed returns embedding vector" do
    mock_vector = [ 0.1, 0.2, 0.3 ]

    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [] }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:post, "#{@ollama_host}/api/embeddings")
      .to_return(status: 200, body: { embedding: mock_vector }.to_json, headers: { "Content-Type" => "application/json" })

    result = OllamaService.embed("test text")

    assert_equal mock_vector, result
  end

  test "embed raises UnavailableError when Ollama is not available" do
    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 500, body: "Internal Server Error")

    assert_raises OllamaService::UnavailableError do
      OllamaService.embed("test text")
    end
  end

  test "embed raises Error on API failure" do
    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [] }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:post, "#{@ollama_host}/api/embeddings")
      .to_return(status: 500, body: "Internal Server Error")

    assert_raises OllamaService::Error do
      OllamaService.embed("test text")
    end
  end
end

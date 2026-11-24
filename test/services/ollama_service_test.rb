require "test_helper"

class OllamaServiceTest < ActiveSupport::TestCase
  setup do
    WebMock.disable_net_connect!
    @ollama_host = Rails.application.config.ollama.host
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "available? uses the native tags endpoint" do
    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [] }.to_json, headers: { "Content-Type" => "application/json" })

    assert OllamaService.available?
  end

  test "embed uses the native embeddings endpoint" do
    mock_vector = [ 0.1, 0.2, 0.3 ]
    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [] }.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:post, "#{@ollama_host}/api/embeddings")
      .with { |request| JSON.parse(request.body)["prompt"] == "test text" }
      .to_return(status: 200, body: { embedding: mock_vector }.to_json, headers: { "Content-Type" => "application/json" })

    assert_equal mock_vector, OllamaService.embed("test text")
  end

  test "generate_json sends a native format payload" do
    schema = { type: "object", required: [ "value" ] }
    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [] }.to_json, headers: { "Content-Type" => "application/json" })
    request = stub_request(:post, "#{@ollama_host}/api/generate")
      .with { |request| JSON.parse(request.body)["format"] == schema.deep_stringify_keys }
      .to_return(
        status: 200,
        body: { response: { value: "ok" }.to_json }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    assert_equal({ "value" => "ok" }, OllamaService.generate_json("Return JSON", schema: schema))
    assert_requested request
  end
end

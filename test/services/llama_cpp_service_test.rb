require "test_helper"

class LlamaCppServiceTest < ActiveSupport::TestCase
  setup do
    WebMock.disable_net_connect!
    @host = Rails.application.config.ollama.host
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "available? uses the OpenAI models endpoint" do
    stub_request(:get, "#{@host}/v1/models")
      .to_return(status: 200, body: { data: [] }.to_json, headers: { "Content-Type" => "application/json" })

    assert LlamaCppService.available?
  end

  test "embed uses the OpenAI embeddings endpoint" do
    mock_vector = [ 0.1, 0.2, 0.3 ]
    stub_request(:get, "#{@host}/v1/models")
      .to_return(status: 200, body: { data: [] }.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:post, "#{@host}/v1/embeddings")
      .with { |request| JSON.parse(request.body)["input"] == "test text" }
      .to_return(status: 200, body: { data: [ { embedding: mock_vector } ] }.to_json, headers: { "Content-Type" => "application/json" })

    assert_equal mock_vector, LlamaCppService.embed("test text")
  end

  test "generate_json sends a JSON schema response format" do
    schema = { type: "object", required: [ "value" ] }
    stub_request(:get, "#{@host}/v1/models")
      .to_return(status: 200, body: { data: [] }.to_json, headers: { "Content-Type" => "application/json" })
    request = stub_request(:post, "#{@host}/v1/chat/completions")
      .with { |request| JSON.parse(request.body).dig("response_format", "json_schema", "schema") == schema.deep_stringify_keys }
      .to_return(
        status: 200,
        body: { choices: [ { message: { content: { value: "ok" }.to_json } } ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    assert_equal({ "value" => "ok" }, LlamaCppService.generate_json("Return JSON", schema: schema))
    assert_requested request
  end
end

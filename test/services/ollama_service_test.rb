require "test_helper"

class OllamaServiceTest < ActiveSupport::TestCase
  test "config uses environment variables with defaults" do
    config = Rails.application.config.ollama

    assert_respond_to config, :host
    assert_respond_to config, :model
    assert_respond_to config, :timeout

    # Check defaults are set
    assert_not_nil config.host
    assert_not_nil config.model
    assert_kind_of Integer, config.timeout
  end

  test "available? handles connection errors gracefully" do
    # This test verifies the service doesn't raise when Ollama is unreachable
    result = OllamaService.available?
    assert_includes [ true, false ], result
  end

  test "model_available? handles connection errors gracefully" do
    result = OllamaService.model_available?
    assert_includes [ true, false ], result
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
end

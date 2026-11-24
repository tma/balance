require "test_helper"

class LlmServiceTest < ActiveSupport::TestCase
  setup do
    @previous = Rails.application.config.llm_backend
  end

  teardown do
    Rails.application.config.llm_backend = @previous
  end

  test "uses the ollama service by default" do
    Rails.application.config.llm_backend = "ollama"

    assert_equal OllamaService, LlmService.client
  end

  test "uses the llama.cpp service when configured" do
    Rails.application.config.llm_backend = "llama_cpp"

    assert_equal LlamaCppService, LlmService.client
  end

  test "rejects an unknown backend" do
    Rails.application.config.llm_backend = "vulkan"

    assert_raises ArgumentError do
      LlmService.client
    end
  end
end

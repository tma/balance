namespace :llm do
  desc "Benchmark LLM models for Balance tasks (CSV mapping, categorization, etc.)"
  task benchmark: :environment do
    unless OllamaService.available?
      puts "Error: Ollama is not available. Benchmark requires a running Ollama instance."
      exit 1
    end

    require_relative "../../lib/llm_benchmark"

    models = ENV.fetch("MODELS", "llama3.1:8b,mistral:7b,mistral-nemo:12b,gemma3:4b,gemma3:12b,gemma3n:e4b,qwen3:4b,qwen3:8b").split(",").map(&:strip)

    benchmark = LlmBenchmark.new(models: models)
    results = benchmark.run
    benchmark.report(results)

    exit(results ? 0 : 1)
  end
end

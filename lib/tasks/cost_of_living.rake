namespace :cost_of_living do
  desc "Benchmark Cost of Living Ollama prompt with synthetic candidates"
  task benchmark: :environment do
    unless OllamaService.available?
      puts "Error: Ollama is not available. Benchmark requires real model calls."
      exit 1
    end

    require_relative "../cost_of_living_prompt_benchmark"

    result = CostOfLivingPromptBenchmark.new.run
    exit(result[:all_passed] ? 0 : 1)
  end
end

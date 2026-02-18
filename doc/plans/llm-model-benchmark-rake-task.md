# LLM Model Benchmark Rake Task

## Problem
We need a way to compare different Ollama LLM models for Balance's tasks
(CSV mapping, transaction extraction, categorization) to make informed
decisions about which model to use. An earlier benchmark script existed on
the `ollama-gemma3-benchmark` branch but was never merged and wasn't exposed
as a rake task.

## Solution
Create `lib/llm_benchmark.rb` and `lib/tasks/llm.rake` following the same
pattern as the existing `categorization:benchmark` rake task. The benchmark:

1. Accepts a comma-separated list of models via `MODELS` env var
   (defaults to `llama3.1:8b,nemotron-3-nano`)
2. Runs test cases aligned with actual production prompts (CSV mapping,
   merchant extraction, single categorization)
3. Calls Ollama directly with each model (overriding the configured model)
5. Prints a comparison table with scores, accuracy, and timing
6. Saves results to `tmp/llm_benchmark_results.json` for later reference

## Usage
```bash
docker exec balance-devcontainer bin/rails llm:benchmark
docker exec balance-devcontainer bin/rails llm:benchmark MODELS=llama3.1:8b,nemotron-3-nano
docker exec balance-devcontainer bin/rails llm:benchmark MODELS=gemma3:12b,qwen3:8b,llama3.1:8b
```

## Files
- `doc/plans/llm-model-benchmark-rake-task.md` — this plan
- `lib/llm_benchmark.rb` — benchmark runner class
- `lib/tasks/llm.rake` — rake task (`llm:benchmark`)

## Notes
- Does NOT require Rails models/DB — uses raw Ollama HTTP calls
- Skips models that aren't pulled locally
- Results are saved incrementally (re-run skips completed models; delete
  `tmp/llm_benchmark_results.json` to reset)
- Removed PDF-related test cases (PDF import was removed per `remove-pdf-import.md`)

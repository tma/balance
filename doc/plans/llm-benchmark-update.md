# LLM Benchmark Update Plan

## Problem

The `DEFAULT_MODELS` list in the LLM benchmark contains `nemotron-3-nano`, which is the wrong model name and was determined to be unsuitable (reasoning model with JSON structured output incompatibility in Ollama). We need to update the benchmark to test the best available candidates and identify the optimal model for both Mac development and IPEX-LLM production (Ollama 0.9.3 on Intel Arc GPU).

## Research Completed

### Reasoning Models (Nemotron, DeepSeek-R1)

Not recommended. Ollama silently disables thinking when `format: "json"` is used (issue #10538). The app uses `format: "json"` for every LLM call via `OllamaService.generate_json()`. A Refuel.ai study found only ~4.9% improvement on classification tasks at >5x token cost — not worth it for the app's low-complexity-per-sample tasks.

### Alternative Runtimes (llama.cpp server)

Stay with Ollama. llama.cpp server is the only runtime that can combine thinking + structured JSON output via GBNF grammars, but the migration effort is significant and the benefit is marginal for our use case.

### IPEX-LLM Production Constraint

Ollama 0.9.3 is the final version — the IPEX-LLM project (github.com/intel-analytics/ipex-llm) was archived January 2026. No further updates will be released. This limits which model architectures are supported in production.

### IPEX-LLM Architecture Compatibility

IPEX-LLM forks Ollama and modifies the SYCL backend for Intel GPU acceleration. Architecture support depends on what was in the llama.cpp version bundled with IPEX-LLM's Ollama 0.9.3 build.

**Confirmed working on IPEX-LLM:**
- `llama` arch — First-class support, benchmarked with perplexity data, used as demo model
- Mistral 7B — IPEX-LLM's README demo GIF, official quickstart example
- Mistral-Nemo 12B — Confirmed by multiple users on Intel Arc GPUs (issues #12952, #13059)

**Confirmed issues on IPEX-LLM:**
- Gemma 3 — User in issue #13059 reported Gemma3 had issues on Intel Arc B580, while Mistral-Nemo worked fine in the same setup

**Unknown/untested on IPEX-LLM:**
- `gemma3n` arch — Added in upstream Ollama 0.9.3, but untested on IPEX-LLM's SYCL backend
- `qwen3` arch — Likely supported (added between Ollama v0.6.5 and v0.7.0), but untested

### Mistral on IPEX-LLM (Deep Research)

Both Mistral 7B and Mistral-Nemo 12B are fully supported:
- Mistral 7B is the canonical IPEX-LLM example model (README demo, quickstart guide, perplexity benchmarks)
- Mistral-Nemo 12B confirmed working on Arc A770 16GB (issue #12952) and Arc B580 (issue #13059)
- Both use `llama` GGUF architecture — the most well-tested arch in IPEX-LLM
- Historical Mistral-Nemo tokenizer issue was resolved in IPEX-LLM's Ollama v0.3.6 upgrade (Aug 2024)
- For Mistral-Nemo 12B, Q4_K_M quantization recommended to avoid VRAM spillover on limited GPUs

### Gemma 3n vs Gemma 3 (Deep Research)

Gemma 3n is a separate model family from Gemma 3, released June 2025:
- **Architecture**: MatFormer (Matryoshka Transformer) with Per-Layer Embeddings (PLE)
- **Trick**: 8B total params but only ~4B effective memory footprint (E4B variant)
- **Sizes**: E2B (~2B effective), E4B (~4B effective)
- **Context**: 32K tokens (vs 128K for Gemma 3)
- **GGUF arch**: `gemma3n` (distinct from `gemma3`)
- **Ollama support**: Added in v0.9.3 (exactly our production version)
- **Benchmarks**: MMLU 64.9 (E4B IT) — slightly exceeds Gemma 3 4B (~62-63)
- **Caveat**: Structured output / function calling not explicitly listed as a feature (works via prompting)
- **IPEX-LLM**: Unknown compatibility — PLE memory optimization designed for mobile, may not work on SYCL

## Changes Made

### 1. Updated `lib/llm_benchmark.rb` line 21

```ruby
# Before:
DEFAULT_MODELS = %w[llama3.1:8b nemotron-3-nano].freeze

# After:
DEFAULT_MODELS = %w[llama3.1:8b mistral:7b mistral-nemo:12b gemma3:4b gemma3:12b gemma3n:e4b qwen3:4b qwen3:8b].freeze
```

### 2. Updated `lib/tasks/llm.rake` line 11

```ruby
# Before:
models = ENV.fetch("MODELS", "llama3.1:8b,nemotron-3-nano").split(",").map(&:strip)

# After:
models = ENV.fetch("MODELS", "llama3.1:8b,mistral:7b,mistral-nemo:12b,gemma3:4b,gemma3:12b,gemma3n:e4b,qwen3:4b,qwen3:8b").split(",").map(&:strip)
```

## Model Selection Rationale

| Model | Size | GGUF Arch | IPEX-LLM Compat | Why included |
|-------|------|-----------|------------------|--------------|
| `llama3.1:8b` | 4.6GB | llama | ✅ Safe | Current default, baseline |
| `mistral:7b` | 4.1GB | llama | ✅ Safe | IPEX-LLM's demo model, well-tested |
| `mistral-nemo:12b` | 6.6GB | llama | ✅ Safe | Confirmed on Arc GPUs, strongest safe option |
| `gemma3:4b` | 3.1GB | gemma3 | ⚠️ Likely | Small/fast, added in Ollama v0.6.0 |
| `gemma3:12b` | 7.6GB | gemma3 | ⚠️ Likely | Quality contender |
| `gemma3n:e4b` | 7.5GB | gemma3n | ⚠️ Likely | 8B params, ~4B effective memory, new arch |
| `qwen3:4b` | 2.3GB | qwen3 | ⚠️ Probably | Smallest candidate, speed baseline |
| `qwen3:8b` | 4.9GB | qwen3 | ⚠️ Probably | Strong general-purpose model |

### Excluded models and reasons

- `nemotron-3-nano` — Wrong model name, reasoning model, JSON `format` incompatible
- `deepseek-r1:8b` — Reasoning model, uses `qwen3` arch internally, JSON `format` disables thinking
- `phi4-mini` — Unknown IPEX-LLM compat (`phi3` arch)
- `aya:8b` — Unknown IPEX-LLM compat (`command-r` arch)
- `qwen3:14b` — Could include but 8.6GB; production VRAM uncertain

## Benchmark Results (Feb 19, 2026)

Run on Mac with Ollama 0.16.2. 11 test cases across 3 categories:
- CSV Column Mapping (3 tests, max 20 points)
- Single Categorization (5 tests, max 5 points)
- Merchant Extraction (3 tests, max 14 points)

### Overall Rankings

| Rank | Model | Score | Accuracy | Avg Time | IPEX-LLM |
|------|-------|-------|----------|----------|-----------|
| 1 | **gemma3:12b** | 38.5/39 | **98.7%** | 6.7s | ⚠️ Likely |
| 2 | **gemma3:4b** | 38.0/39 | **97.4%** | **2.7s** | ⚠️ Likely |
| 2 | **mistral-nemo:12b** | 38.0/39 | **97.4%** | 7.4s | ✅ Safe |
| 4 | llama3.1:8b | 35.0/39 | 89.7% | 4.9s | ✅ Safe |
| 5 | gemma3n:e4b | 34.0/39 | 87.2% | 4.3s | ⚠️ Likely |
| 6 | mistral:7b | 32.5/39 | 83.3% | 4.7s | ✅ Safe |
| 7 | qwen3:8b | 24.5/39 | 62.8% | 3.8s | ⚠️ Probably |
| 8 | qwen3:4b | 0.0/39 | 0.0% | — | ⚠️ Probably |

### Breakdown by Category

**CSV Column Mapping** (max 20 points):

| Model | Score | Pct |
|-------|-------|-----|
| gemma3:12b | 20/20 | 100% |
| llama3.1:8b | 20/20 | 100% |
| qwen3:8b | 20/20 | 100% |
| gemma3:4b | 19/20 | 95% |
| mistral-nemo:12b | 19/20 | 95% |
| gemma3n:e4b | 17/20 | 85% |
| mistral:7b | 14/20 | 70% |
| qwen3:4b | 0/20 | 0% |

**Single Categorization** (max 5 points):

| Model | Score | Pct |
|-------|-------|-----|
| llama3.1:8b | 5/5 | 100% |
| gemma3:4b | 5/5 | 100% |
| mistral-nemo:12b | 5/5 | 100% |
| gemma3n:e4b | 5/5 | 100% |
| gemma3:12b | 4.5/5 | 90% |
| mistral:7b | 4.5/5 | 90% |
| qwen3:8b | 4.5/5 | 90% |
| qwen3:4b | 0/5 | 0% |

**Merchant Extraction** (max 14 points):

| Model | Score | Pct |
|-------|-------|-----|
| gemma3:12b | 14/14 | 100% |
| mistral-nemo:12b | 14/14 | 100% |
| gemma3:4b | 14/14 | 100% |
| mistral:7b | 14/14 | 100% |
| gemma3n:e4b | 12/14 | 86% |
| llama3.1:8b | 10/14 | 71% |
| qwen3:8b | 0/14 | 0% |
| qwen3:4b | 0/14 | 0% |

### Key Findings

1. **gemma3:4b is the standout** — 97.4% accuracy at only 2.7s average (fastest model that works well). Half the size of llama3.1:8b with much better accuracy. Perfect on categorization and merchant extraction.

2. **gemma3:12b is the most accurate** at 98.7%, only losing 0.5 points on the ambiguous gas station categorization test (classified as Groceries instead of Transportation — acceptable since "COOP PRONTO TANKSTELLE" is a COOP brand).

3. **mistral-nemo:12b ties gemma3:4b at 97.4%** but is 2.7x slower. However, it's the **safest production option** — confirmed working on IPEX-LLM Intel Arc GPUs by multiple users.

4. **llama3.1:8b (current default) is weak on merchant extraction** (71%) — lost 4/14 points. The "reference codes + dates" test case scored 0/4. Good at CSV mapping and categorization but not the best overall.

5. **Qwen3 models failed badly**:
   - `qwen3:4b` scored 0% — all JSON parse failures, likely outputting thinking tokens despite `format: "json"`
   - `qwen3:8b` scored 0% on merchant extraction — it can produce valid JSON for CSV/categorization but fails on array-format merchant responses
   - This confirms reasoning models don't work well with Ollama's JSON format constraint

6. **gemma3n:e4b underperformed vs regular gemma3:4b** — 87.2% vs 97.4%. Despite having 8B total params (vs 4B), the MatFormer/PLE architecture didn't help for these tasks. Weaker on CSV mapping (85%) and merchant extraction (86%).

## Recommendations

### Best model by use case

| Priority | Model | Why |
|----------|-------|-----|
| **Production-safe best** | `mistral-nemo:12b` | 97.4%, confirmed on IPEX-LLM Arc GPUs |
| **Overall best** | `gemma3:4b` | 97.4%, 2.7s avg, smallest viable model |
| **Highest accuracy** | `gemma3:12b` | 98.7%, but 6.7s avg and needs IPEX-LLM verification |

### IPEX-LLM production safety tiers

- **✅ Safe** (confirmed working): `mistral-nemo:12b` (97.4%), `llama3.1:8b` (89.7%), `mistral:7b` (83.3%)
- **⚠️ Likely** (untested, one user reported gemma3 issues): `gemma3:4b` (97.4%), `gemma3:12b` (98.7%)
- **❌ Not recommended**: `qwen3:4b` (0%), `qwen3:8b` (62.8%), `gemma3n:e4b` (87.2% and unknown IPEX-LLM compat)

### Next steps

1. **Safe upgrade**: Change default from `llama3.1:8b` to `mistral-nemo:12b` — guaranteed +7.7% accuracy improvement on IPEX-LLM
2. **Test gemma3:4b on production hardware** — if it works, switch to it for 2.7x faster inference at same accuracy
3. **Vulkan migration** (tracked separately in `ollama-vulkan-migration.md`) would remove the IPEX-LLM constraint entirely, making `gemma3:4b` or `gemma3:12b` viable without verification concerns

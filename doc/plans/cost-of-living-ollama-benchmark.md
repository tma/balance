# Cost of Living Ollama Prompt Benchmark

## Problem

The Cost of Living feature uses the configured local Ollama model to suggest
essentiality for grouped expense streams, but the production prompt has only
been tested for malformed-response safety. The existing categorization benchmark
tests a different prompt and cannot establish accuracy for these suggestions.

## Solution

Add a repeatable benchmark that invokes the exact production prompt against the
configured Ollama model.

The benchmark will:

- Use labeled synthetic candidates spanning housing, utilities, food,
  healthcare, transportation, subscriptions, leisure, savings, transfers, debt
  payments, and category-dependent ambiguous merchants.
- Score essential/discretionary/excluded classification separately from the
  advisory recurring/non-recurring/unknown hint.
- Validate that every candidate appears exactly once with valid enum values.
- Run multiple rounds to expose unstable classifications.
- Print per-case failures, aggregate accuracy, schema validity, and stability.
- Exit nonzero below explicit thresholds so it can be used before deployment.

The production prompt will be exposed through one shared builder so the benchmark
cannot drift from runtime behavior. If the first run exposes systematic errors,
the prompt will be clarified and rerun against the same fixed dataset.

## Files

- `app/services/expense_profile_detection_service.rb`
- `lib/cost_of_living_prompt_benchmark.rb`
- `lib/tasks/cost_of_living.rake`
- `test/services/expense_profile_detection_service_test.rb`
- `SPEC.md`

## Considerations

- The benchmark uses real local model calls and is intentionally outside the
  normal test suite.
- Recurrence output remains advisory; deterministic Ruby cadence detection is
  authoritative in production.
- Synthetic labels encode a minimum-living-cost interpretation, not whether an
  expense is personally valuable.
- Results are model-specific and must report the configured model name.

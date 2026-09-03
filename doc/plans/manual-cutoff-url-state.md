# Manual Cutoff URL State

## Problem

A manual cutoff is persisted but not visible in the Cost of Living URL, and the
success notice describes internal grouped-stream processing rather than the
user-visible result.

## Solution

- Add `through=YYYY-MM` to the Cost of Living URL for non-default cutoffs.
- Honor a valid `through` value when rendering a direct URL.
- Keep the clean URL when the selected month equals the coverage default.
- Replace the technical notice with wording that states the selected month and
  explains that profile suggestions are refreshing in the background.

## Files

- `CostOfLivingPeriodService`
- Dashboard and Cost of Living settings controllers
- Related service/controller tests

## Considerations

The persisted setting remains the durable default for background import
analysis. The URL makes the current non-default view explicit and shareable.

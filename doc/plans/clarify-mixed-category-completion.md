# Clarify Mixed Category Completion

## Problem

Users can select `Mixed` for a category but cannot reach 100% completeness while
unmatched transactions remain in that category. The interface presents `Mixed`
like a final choice and does not explain that confirmed profiles override a
category fallback, making completion appear impossible.

## Solution

Describe Section 1 choices as defaults for spending not covered by a confirmed
profile. Label `Mixed` as incomplete and tell users to choose Essential,
Discretionary, or Excluded as the fallback for categories named in the warning.

## Files

- `app/views/dashboard/cash_flow_cost_of_living.html.erb`
- `test/controllers/dashboard_controller_test.rb`

## Considerations

No projection behavior changes. Existing mixed classifications remain intact and
users retain explicit control over the appropriate fallback.

# Neutral Mixed Remainder

## Problem

An intentional `Mixed` category leaves unmatched spending outside the baseline.
The page currently treats that expected remainder as an incomplete-state alert,
which implies users must eliminate `Mixed` and reach 100%.

## Solution

Separate actionable review state from baseline coverage:

- Unclassified categories and open profile suggestions remain actionable alerts.
- Mixed-category remainder becomes a neutral line in the persistent breakdown.
- `Mixed` returns to being a valid steady-state label.
- Report completion means no actionable unclassified categories or suggestions;
  classified-spend coverage remains a separate percentage.

## Files

- `app/services/cost_of_living_projection_service.rb`
- `app/views/dashboard/cash_flow_cost_of_living.html.erb`
- `test/services/cost_of_living_projection_service_test.rb`
- `test/controllers/dashboard_controller_test.rb`
- `SPEC.md`

## Considerations

Mixed unmatched spending remains excluded from the essential-cost headline, so
the breakdown must always disclose both its annual value and coverage percentage.
No historical classifications or transactions are changed.

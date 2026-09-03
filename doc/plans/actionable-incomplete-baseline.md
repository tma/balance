# Actionable Incomplete Baseline

## Problem

The incomplete-estimate banner can report excluded spending while the grouped
expense-stream review queue is empty. This happens when transactions belong to
categories whose classification is `Mixed` or unset and do not match a confirmed
expense profile. The page does not identify those categories, so the warning
appears to have no available resolution.

## Solution

Expose unresolved spending grouped by category from the projection service.
In the warning banner, link those categories directly to their controls in
Section 1 and explain that they need a final category classification. Preserve
the separate Section 2 guidance when grouped suggestions are open.

## Files

- `app/services/cost_of_living_projection_service.rb`
- `app/views/dashboard/cash_flow_cost_of_living.html.erb`
- `test/services/cost_of_living_projection_service_test.rb`

## Considerations

The calculation and headline values remain unchanged. The new breakdown is
derived from the same transaction classifications used for completeness, so the
guidance cannot drift from the warning.

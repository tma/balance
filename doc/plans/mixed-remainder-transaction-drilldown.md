# Mixed Remainder Transaction Drill-Down

## Problem

The baseline breakdown discloses an annual mixed-category remainder but does not
let users inspect the transactions behind it. Ordinary category links are not
exact because they also include transactions already covered by confirmed
profiles.

## Solution

Expose the exact mixed-remainder transaction IDs from the projection service and
add a dedicated Transactions index filter. Link the breakdown label to that
filter and show a clear filtered-state heading with a return link.

## Files

- `app/services/cost_of_living_projection_service.rb`
- `app/controllers/transactions_controller.rb`
- `app/views/dashboard/cash_flow_cost_of_living.html.erb`
- `app/views/transactions/index.html.erb`
- `test/services/cost_of_living_projection_service_test.rb`
- `test/controllers/transactions_controller_test.rb`
- `test/controllers/dashboard_controller_test.rb`
- `SPEC.md`

## Considerations

The drill-down must use the same reporting window, incomplete-month exclusions,
confirmed-profile matching, and classification precedence as the displayed
remainder. It must not approximate the result with category-only filtering.

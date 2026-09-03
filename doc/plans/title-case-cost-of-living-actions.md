# Title-Case Cost of Living Actions

## Problem

Cost of Living action labels inconsistently use sentence case, while application
buttons should use title case.

## Solution

Update the Cost of Living page and expense-profile editor action labels to title
case without changing their behavior.

## Files

- `app/views/dashboard/cash_flow_cost_of_living.html.erb`
- `app/views/expense_profiles/edit.html.erb`
- `test/controllers/dashboard_controller_test.rb`

## Considerations

Navigation labels and non-action explanatory copy remain unchanged.

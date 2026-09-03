# Preselect Coverage Cutoff Month

## Problem

Showing Automatic as a separate dropdown option makes it look like a value
instead of the source of the preselected cutoff month.

## Solution

List only calendar months and preselect the effective coverage-derived month.
After a user applies another month, show a separate Use Coverage Default action
to clear the override.

## Files

- `app/views/dashboard/cash_flow_cost_of_living.html.erb`
- `test/controllers/dashboard_controller_test.rb`

## Considerations

The automatic/manual source disclosure remains visible below the toolbar.

# Inline Cost of Living Cutoff

## Problem

The Data Complete Through selector occupies a separate card, while it functions
as report navigation alongside Refresh Suggestions.

## Solution

Move the selector and Apply action into the sticky report toolbar immediately
to the left of Refresh Suggestions. Keep the effective date-window disclosure
as compact supporting text below the toolbar.

## Files

- `app/views/dashboard/cash_flow_cost_of_living.html.erb`
- `test/controllers/dashboard_controller_test.rb`

## Considerations

The controls remain one line on normal desktop widths and can horizontally
scroll rather than splitting internally on narrow screens.

# Valuations Form Fixes

## Issues

### 1. Copy Next Month Button Position
**Problem**: The "copy next month" arrow button (→) currently appears in the last column (January of next year), which is always December behavior. 

**Expected**: The button should appear in the **previous month column** relative to the **current month**. This allows users to copy the previous month's value into the current month.

**Solution**: Change the logic from:
- `is_last` (last column) → show copy button
- `is_second_last` (second to last) → source value

To:
- Month **before current month** → show copy button (destination)
- Month **two before current month** → source value

### 2. Current Month Column Highlighting
**Problem**: Currently only the header text style changes for the current month, but the asset cells don't have any background highlighting.

**Expected**: The current month column should have a light background highlight on asset cells (but NOT on group headers which have their own styling).

**Solution**: Add a light background class to `<td>` cells for asset rows when the column is the current month.

## Files to Modify

- `app/views/asset_valuations/bulk_edit.html.erb`
  - Lines 121-122: Change `is_last`/`is_second_last` logic to be relative to current month
  - Lines 125-131: Update copy button condition
  - Lines 144-145: Update source/destination target conditions
  - Lines 117: Add current month background to active asset cells
  - Lines 184: Add current month background to archived asset cells

## Implementation Notes

- Need to find the index of the current month in the `@months` array
- Copy button goes on month at `current_month_index - 1` (previous month)
- Source for copy is at `current_month_index - 2` (two months before)
- Background highlight should be subtle: `bg-blue-50 dark:bg-blue-950/30` or similar
- Only apply to asset value cells, not group headers or totals

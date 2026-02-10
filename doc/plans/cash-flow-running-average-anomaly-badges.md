# Cash Flow: Running Average/Baseline + Anomaly Badges

## Problem
The monthly breakdown table in the cash flow year view shows raw numbers per month, but provides no context for whether a month's expenses are unusually high. Users need a baseline to compare against and visual flags for outlier months.

## Solution
Add a trailing 12-month rolling average for expenses, display it in the monthly table, and flag months where expenses exceed the average by 20% or more with a "High" badge.

## Implementation

### 1. Backend: `enrich_monthly_data_with_averages` method (DashboardController)
- New private method that takes the selected year and monthly_data array
- For each month (Jan-Dec of the selected year), look back 12 months (excluding the current month)
- Query `Transaction.expense.in_month(y, m).sum(:amount_in_default_currency)` for each trailing month
- Compute `trailing_average` = mean of available trailing months' expenses
- Compute `delta_percent` = `(month_expenses - trailing_average) / trailing_average` (nil if average is 0)
- Flag `anomaly: true` when `delta_percent >= 20.0`
- For first months with < 12 trailing months, use whatever is available; show "—" if 0 trailing months
- Return enriched monthly_data with `:trailing_average`, `:delta_percent`, `:anomaly` keys

### 2. Controller changes
- In `cash_flow` action, call the new method to enrich `@monthly_data` with average/anomaly data
- Footer row shows the latest available trailing average for the year

### 3. View changes (cash_flow.html.erb, monthly breakdown table)
- Add "12-Month Average" column header between "Expenses" and "Net"
- For each month row, show the 12-month average expense value (or "—" if insufficient data)
- Add inline anomaly badge after the Expenses value when `anomaly: true`:
  `<span class="ui_badge_warning_class" title=">20% above 12-month average">High</span>`
- Totals row shows the latest available trailing average

### 4. Edge cases
- Months with 0 trailing data: show "—" for average, no anomaly badge
- Months with < 12 trailing months: use available months only (partial average)
- Future months: skip anomaly calculation, show "—"
- Zero average: skip delta calculation (avoid division by zero)

### 5. Tests
- **Unit test**: `CashFlowAverageTest` in `test/controllers/`
  - Test with 12+ months of data: correct average and anomaly flag
  - Test with < 12 months: partial average
  - Test with 0 trailing months: returns nil/dash
  - Test anomaly threshold: 19% = no flag, 20% = flag, 50% = flag
- **View/integration test**: `DashboardControllerTest`
  - Test that "High" badge appears for anomalous months
  - Test that "12-Month Average" label appears in the table
  - Test that "—" appears for months with insufficient data

## Files to modify
- `app/controllers/dashboard_controller.rb` - new method + call in action
- `app/views/dashboard/cash_flow.html.erb` - table column + badge + footer row
- `test/controllers/dashboard_controller_test.rb` - integration tests
- `test/fixtures/transactions.yml` - additional fixtures for test data

## Design decisions
- Track expenses only (not income/net) for anomaly detection — expense spikes are the primary concern
- Use trailing 12-month window (not calendar year) for the baseline — accounts for seasonal patterns
- 20% threshold is the initial default — could be made configurable later
- Badge uses warning style (amber) to distinguish from the info badge used for "Current" month

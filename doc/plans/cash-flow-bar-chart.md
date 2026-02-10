# Cash Flow Bar Chart

## Problem
The monthly breakdown table shows raw numbers but lacks a visual overview of income vs. expenses across the year. The trailing 12-month average data is computed but only surfaced via small "High" anomaly badges.

## Solution
Add a grouped bar chart (income + expenses per month) with a trailing average overlay line, placed above the monthly breakdown table in the year view.

## Design

### Chart structure (following the net_worth stacked bar pattern)
- SVG with `viewBox="0 0 100 <height>"`, `preserveAspectRatio="none"`, `class="w-full"`
- Fixed height: 150px
- Y-axis labels on the left (using `chart_y_ticks` and `format_y_axis_value`)
- X-axis month labels below

### Bars
- **Grouped bars**: For each month, two bars side by side — income (emerald) and expenses (rose)
- Bar width: ~3.5% each (total ~7% per month pair + ~1.33% gap between months)
- Income bar: `#34d399` (emerald-400)
- Expenses bar: `#fb7185` (rose-400)
- Anomaly months: expenses bar uses a brighter/darker shade or gets a pattern

### Trailing average line
- Dashed `<line>` or `<polyline>` connecting trailing_average values across months
- Color: slate-400 with `stroke-dasharray="4 3"`
- Only drawn between months that have a trailing_average value
- Uses `vector-effect="non-scaling-stroke"` for consistent dash appearance

### Tooltips
- Reuse existing `chart-tooltip` Stimulus controller with `data-chart-tooltip-always-above-value="true"`
- Invisible overlay rects per month group for hover detection
- Tooltip text: "Jan 2026 · Income: CHF 5'000 / Expenses: CHF 1'500 / Net: +CHF 3'500"
- Render `shared/chart_tooltip` partial

### Legend
- Small color swatches + labels below the chart: Income (emerald), Expenses (rose), 12-Mo Avg (dashed line)

## Files to modify
- `app/views/dashboard/cash_flow.html.erb` — add chart section above the monthly breakdown table
- `test/controllers/dashboard_cash_flow_average_test.rb` — add view tests for chart SVG presence

## Files NOT modified
- Controller — `@monthly_data` already has all the data we need (income, expenses, trailing_average)
- Stimulus controller — reusing existing `chart-tooltip` controller
- Helpers — reusing existing `chart_y_ticks`, `format_y_axis_value`, `format_currency_plain`

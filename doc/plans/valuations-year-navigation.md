# Valuations Form Year-Based Navigation

## Problem

The current valuations form shows a rolling 12-month window with navigation that shifts by 12 months at a time. This makes it awkward to view a full calendar year and compare year-over-year data.

## Solution

Change the navigation to be year-based, showing 14 columns: **Dec of previous year** + **full calendar year (Jan-Dec)** + **Jan of next year**. The adjacent months (Dec before and Jan after) will be visually dimmed but still editable to provide context at year boundaries.

## Specifications

| Aspect | Current | New |
|--------|---------|-----|
| Columns | 12 rolling months | 14 months (Dec prev + full year + Jan next) |
| Navigation | ± 12 months | ± 1 year |
| URL param | `?month=2025-06` | `?year=2025` |
| Default | Current month | Current calendar year |
| Forward limit | Current month | Current year + 1 |
| Adjacent months | N/A | Dimmed but editable |
| Form submit | Resets to default | Stays on same year |

## Files to Modify

1. `app/controllers/asset_valuations_controller.rb`
   - Parse `year` param instead of `month`
   - Update `build_months_range` to return 14 months
   - Preserve year param on redirect after save

2. `app/views/asset_valuations/bulk_edit.html.erb`
   - Update navigation to year-based (← 2024 | 2025 | 2026 →)
   - Add hidden year field to form
   - Apply dimmed styling to adjacent-year columns (Dec before, Jan after)
   - Update tabindex calculations for 14 columns

## Implementation Details

### Controller Changes

**`bulk_edit` action:**
```ruby
# Parse year parameter or default to current year
if params[:year].present?
  @year = params[:year].to_i
else
  @year = Date.current.year
end

# Limit to current year + 1 max
max_year = Date.current.year + 1
@year = [@year, max_year].min
```

**`build_months_range` method:**
```ruby
def build_months_range(year)
  # 14 months: Dec of prev year, full year, Jan of next year
  months = []
  months << Date.new(year - 1, 12, 1).end_of_month
  (1..12).each { |m| months << Date.new(year, m, 1).end_of_month }
  months << Date.new(year + 1, 1, 1).end_of_month
  months
end
```

**`bulk_update` redirect:**
```ruby
redirect_to update_valuations_path(year: params[:year]), notice: "..."
```

### View Changes

**Navigation (replace lines 11-26):**
```erb
<div class="flex items-center space-x-2">
  <%= link_to update_valuations_path(year: @year - 1), class: ui_btn_secondary_class + " text-sm" do %>
    ← <%= @year - 1 %>
  <% end %>
  
  <span class="px-3 py-1.5 font-semibold text-sm"><%= @year %></span>
  
  <% max_year = Date.current.year + 1 %>
  <% if @year < max_year %>
    <%= link_to update_valuations_path(year: @year + 1), class: ui_btn_secondary_class + " text-sm" do %>
      <%= @year + 1 %> →
    <% end %>
  <% else %>
    <span class="px-3 py-1.5 rounded-lg bg-slate-50 dark:bg-slate-800 text-slate-300 dark:text-slate-600 text-sm font-medium"><%= max_year + 1 %> →</span>
  <% end %>
</div>
```

**Form hidden field:**
```erb
<%= form_with url: update_valuations_path, method: :patch, ... do |form| %>
  <%= hidden_field_tag :year, @year %>
```

**Dimmed styling for adjacent months:**
```erb
<% is_adjacent = month.year != @year %>
```

Apply to:
- Column headers: add `opacity-50` class
- Cell backgrounds: add `bg-slate-100 dark:bg-slate-900`
- Input text: add `text-slate-400 dark:text-slate-500`
- Group header cells
- Group totals cells
- Total Net Worth cells

## Visual Result

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Valuations                                          ← 2025 | 2026 | 2027 → │
├─────────────────────────────────────────────────────────────────────────────┤
│ Asset      │ Dec'25 │ Jan'26 │ Feb'26 │ ... │ Dec'26 │ Jan'27 │
│            │ (dim)  │        │        │     │        │ (dim)  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Edge Cases

- **Max year**: Cannot navigate past current year + 1; button is disabled
- **No lower limit**: Can navigate to any historical year
- **Scroll position**: `scroll_right_controller.js` still scrolls right (shows Jan next year)
- **Tabindex**: Recalculate for 14 columns instead of 12

## Testing

- Year navigation forward/backward works
- Max year limit enforced
- Adjacent months render dimmed
- Adjacent month values are editable and save correctly
- Form submit stays on same year
- Default landing shows current year

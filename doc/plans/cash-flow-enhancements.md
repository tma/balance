# Cash Flow Page Enhancements

## Overview

Enhance the cash flow page with:
1. Yearly navigation (Jan-Dec calendar years)
2. Month filter within the selected year
3. Nested donut chart showing income (inner) and expenses+savings (outer)
4. Refined summary cards design
5. Seed data with varied monthly net savings (positive and negative months)

## Current State

- Fixed 12-month rolling window with no navigation
- Summary cards: 4 separate boxes (Income, Expenses, Net Savings, Saving Rate)
- No charts - just horizontal expense/savings bars in table rows
- Budgets always show current month/year context

## Requirements

### 1. Year Navigation
- Navigate between calendar years using prev/next arrows
- URL parameter: `?year=2025`
- Default to current year
- Show all 12 months of the selected year (Jan-Dec)

### 2. Month Filter
- Clickable month tabs/buttons within the displayed year
- URL parameter: `?year=2025&month=3` (for March)
- "All" option shows full year aggregate
- Selected month highlighted in the monthly table
- Donut chart reflects selected period (month or full year)

### 3. Nested Donut Chart
```
┌─────────────────────────────────────────┐
│                                         │
│         ┌───────────────────┐           │
│         │                   │           │
│         │    ┌─────────┐    │           │
│         │    │         │    │           │
│         │    │  NET    │    │           │
│         │    │ ±$XXX   │    │           │
│         │    │         │    │           │
│         │    └─────────┘    │           │
│         │     INCOME        │           │  ← Inner ring
│         │    (by category)  │           │
│         └───────────────────┘           │
│           EXPENSES + SAVINGS            │  ← Outer ring
│          (by category + savings slice)  │
└─────────────────────────────────────────┘
```

**Inner Ring (Income):**
- Shows income broken down by category
- Uses cool tones (blues/teals)

**Outer Ring (Expenses + Savings):**
- Shows expenses broken down by category
- If net > 0: Includes a "Savings" slice (emerald) representing surplus
- Uses warm tones for expenses, emerald for savings

**Center:**
- Shows net amount prominently
- Green if positive, red if negative
- Shows "savings" label if positive, "deficit" if negative

### 4. Summary Cards Refinement

**Current (ugly):**
```
┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
│ Income   │ │ Expenses │ │ Net      │ │ Saving   │
│ $XX,XXX  │ │ $XX,XXX  │ │ ±$X,XXX  │ │ Rate XX% │
└──────────┘ └──────────┘ └──────────┘ └──────────┘
```

**Proposed (refined):**
Replace 4 separate cards with a single compact row showing the flow:

```
┌───────────────────────────────────────────────────────────────┐
│  +$10,500 Income  →  -$8,200 Expenses  =  +$2,300 (22% saved) │
│     ████████████████████████░░░░░░░░                          │
│        ← expenses 78% →       ← saved →                       │
└───────────────────────────────────────────────────────────────┘
```

Or a cleaner horizontal layout:
```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  Income              Expenses            Net Savings    Saving Rate │
│  +$10,500      -     $8,200        =     +$2,300          22%       │
│  ──────────────────────────────────────────────────────────         │
│  ████████████████████████████████░░░░░░░░░░░░                       │
│  ← Expenses 78% ──────────────── │ ── Saved 22% →                   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

Key improvements:
- Single cohesive card instead of 4 separate boxes
- Visual flow showing income → expenses → result
- Integrated progress bar showing expense/savings ratio
- Cleaner, more professional appearance

### 5. Budget Section Updates
- Budgets follow the navigation context
- Monthly budgets: Show progress for selected month (or current month of selected year if no month filter)
- Yearly budgets: Show progress for selected year

### 6. Seed Data - Varied Net Savings

Add specific months with intentionally different scenarios:

| Month | Scenario | Income | Expenses | Net |
|-------|----------|--------|----------|-----|
| Current month | Normal | ~$9,500 | ~$7,500 | +$2,000 |
| 1 month ago | High expenses (travel) | ~$9,500 | ~$11,000 | -$1,500 |
| 2 months ago | Bonus month | ~$14,500 | ~$7,500 | +$7,000 |
| 3 months ago | Normal | ~$9,500 | ~$8,000 | +$1,500 |
| 4 months ago | Medical emergency | ~$9,500 | ~$12,500 | -$3,000 |
| 5 months ago | Normal | ~$9,500 | ~$7,200 | +$2,300 |
| 6 months ago | Break-even | ~$9,500 | ~$9,400 | +$100 |

This ensures the chart and summary cards demonstrate all states:
- Positive savings (most months)
- Negative savings/deficit (2 months with unexpected expenses)
- Large surplus (bonus month)
- Break-even (near zero)

## Files to Modify

| File | Changes |
|------|---------|
| `app/controllers/dashboard_controller.rb` | Year/month params, category breakdown calculations, period navigation |
| `app/views/dashboard/cash_flow.html.erb` | Navigation UI, refined summary, donut chart, updated table, budget context |
| `app/helpers/dashboard_helper.rb` | Chart data building helpers for nested donut |
| `db/seeds.rb` | Add varied monthly scenarios in development data |
| `SPEC.md` | Update Cash Flow View section |

## Implementation Details

### Controller Changes

```ruby
def cash_flow
  @default_currency = Currency.default_code
  
  # Parse year/month from params
  @selected_year = (params[:year] || Date.current.year).to_i
  @selected_month = params[:month]&.to_i  # nil = full year
  
  # Year range for navigation (based on available transactions)
  @min_year = Transaction.minimum(:date)&.year || Date.current.year
  @max_year = Date.current.year
  
  # Monthly data for selected calendar year (Jan-Dec)
  @monthly_data = calculate_monthly_data_for_year(@selected_year)
  @year_totals = calculate_year_totals(@selected_year)
  
  # Period totals (respects month filter)
  @period_totals = calculate_period_totals(@selected_year, @selected_month)
  
  # Category breakdowns for donut chart
  @income_by_category = calculate_category_breakdown(:income, @selected_year, @selected_month)
  @expense_by_category = calculate_category_breakdown(:expense, @selected_year, @selected_month)
  
  # Budgets
  @monthly_budgets = Budget.monthly.includes(:category).order("categories.name")
  @yearly_budgets = Budget.yearly.includes(:category).order("categories.name")
  @budget_year = @selected_year
  @budget_month = @selected_month || Date.current.month
end

private

def calculate_monthly_data_for_year(year)
  (1..12).map do |month|
    month_start = Date.new(year, month, 1)
    income = Transaction.income.in_month(year, month).sum(:amount_in_default_currency) || 0
    expenses = Transaction.expense.in_month(year, month).sum(:amount_in_default_currency) || 0
    net = income - expenses
    saving_rate = income > 0 ? ((net / income) * 100).round(1) : 0
    
    {
      date: month_start,
      year: year,
      month: month,
      month_name: Date::MONTHNAMES[month],
      month_abbr: Date::ABBR_MONTHNAMES[month],
      income: income,
      expenses: expenses,
      net: net,
      saving_rate: saving_rate,
      is_future: month_start > Date.current
    }
  end
end

def calculate_year_totals(year)
  income = Transaction.income.in_year(year).sum(:amount_in_default_currency) || 0
  expenses = Transaction.expense.in_year(year).sum(:amount_in_default_currency) || 0
  net = income - expenses
  saving_rate = income > 0 ? ((net / income) * 100).round(1) : 0
  
  { income: income, expenses: expenses, net: net, saving_rate: saving_rate }
end

def calculate_period_totals(year, month = nil)
  if month
    income = Transaction.income.in_month(year, month).sum(:amount_in_default_currency) || 0
    expenses = Transaction.expense.in_month(year, month).sum(:amount_in_default_currency) || 0
  else
    income = Transaction.income.in_year(year).sum(:amount_in_default_currency) || 0
    expenses = Transaction.expense.in_year(year).sum(:amount_in_default_currency) || 0
  end
  net = income - expenses
  saving_rate = income > 0 ? ((net / income) * 100).round(1) : 0
  
  { income: income, expenses: expenses, net: net, saving_rate: saving_rate }
end

def calculate_category_breakdown(type, year, month = nil)
  scope = Transaction.where(transaction_type: type)
  scope = month ? scope.in_month(year, month) : scope.in_year(year)
  
  scope.joins(:category)
       .group("categories.id", "categories.name")
       .sum(:amount_in_default_currency)
       .map { |(id, name), amount| { id: id, name: name, amount: amount } }
       .sort_by { |c| -c[:amount] }
end
```

### Helper Changes

```ruby
# Color palettes for nested donut
INCOME_COLORS = %w[#0ea5e9 #06b6d4 #14b8a6 #22c55e #84cc16 #10b981].freeze
EXPENSE_COLORS = %w[#f97316 #ef4444 #ec4899 #a855f7 #6366f1 #8b5cf6 #f59e0b #dc2626].freeze
SAVINGS_COLOR = "#10b981"  # emerald-500

def build_nested_donut_data(income_by_category, expense_by_category, period_totals)
  # Build income ring data
  income_data = income_by_category.map.with_index do |cat, idx|
    {
      name: cat[:name],
      value: cat[:amount],
      color: INCOME_COLORS[idx % INCOME_COLORS.length]
    }
  end
  
  # Build expense ring data
  expense_data = expense_by_category.map.with_index do |cat, idx|
    {
      name: cat[:name],
      value: cat[:amount],
      color: EXPENSE_COLORS[idx % EXPENSE_COLORS.length]
    }
  end
  
  # Add savings slice if positive
  savings = period_totals[:net]
  if savings > 0
    expense_data << { name: "Savings", value: savings, color: SAVINGS_COLOR }
  end
  
  # Calculate percentages
  income_total = income_data.sum { |d| d[:value] }
  expense_total = expense_data.sum { |d| d[:value] }
  
  income_data.each { |d| d[:pct] = income_total > 0 ? (d[:value].to_f / income_total * 100).round(1) : 0 }
  expense_data.each { |d| d[:pct] = expense_total > 0 ? (d[:value].to_f / expense_total * 100).round(1) : 0 }
  
  { income: income_data, expenses: expense_data }
end
```

### Seed Data Changes

Replace the random transaction generation with controlled monthly profiles:

```ruby
# Monthly profiles for varied cash flow demonstration
MONTHLY_PROFILES = {
  0 => { description: "Normal month", extra_income: 0, extra_expense: 0 },
  1 => { description: "High expenses (travel)", extra_income: 0, extra_expense: 3500 },
  2 => { description: "Bonus month", extra_income: 5000, extra_expense: 0 },
  3 => { description: "Normal month", extra_income: 0, extra_expense: 500 },
  4 => { description: "Medical emergency", extra_income: 0, extra_expense: 5000 },
  5 => { description: "Normal month", extra_income: 0, extra_expense: 0 },
  6 => { description: "Break-even month", extra_income: 0, extra_expense: 2000 },
  # ... continue for remaining months
}

# Apply profile adjustments when generating transactions
profile = MONTHLY_PROFILES[months_ago] || { extra_income: 0, extra_expense: 0 }

# Add bonus income if specified
if profile[:extra_income] > 0
  create_transaction(
    account: accounts[:main_checking],
    category: income_categories["bonus"],
    amount: profile[:extra_income],
    transaction_type: "income",
    date: month_start + 15.days,
    description: "Performance bonus"
  )
end

# Add extra expenses if specified
if profile[:extra_expense] > 0
  category = case months_ago
             when 1 then expense_categories["travel"]
             when 4 then expense_categories["healthcare"]
             else expense_categories["other expense"]
             end
  create_transaction(
    account: accounts[:visa],
    category: category,
    amount: profile[:extra_expense],
    transaction_type: "expense",
    date: month_start + 10.days,
    description: profile[:description]
  )
end
```

### View Structure

```erb
<%# Year Navigation %>
<div class="flex items-center justify-between mb-4">
  <div class="flex items-center space-x-4">
    <% if @selected_year > @min_year %>
      <%= link_to cash_flow_path(year: @selected_year - 1), class: "..." do %>
        ← <%= @selected_year - 1 %>
      <% end %>
    <% else %>
      <span class="text-slate-300">← <%= @selected_year - 1 %></span>
    <% end %>
    
    <span class="text-xl font-semibold"><%= @selected_year %></span>
    
    <% if @selected_year < @max_year %>
      <%= link_to cash_flow_path(year: @selected_year + 1), class: "..." do %>
        <%= @selected_year + 1 %> →
      <% end %>
    <% else %>
      <span class="text-slate-300"><%= @selected_year + 1 %> →</span>
    <% end %>
  </div>
</div>

<%# Month Filter Tabs %>
<div class="flex flex-wrap gap-1 mb-6">
  <%= link_to "Year", cash_flow_path(year: @selected_year), 
      class: @selected_month.nil? ? "px-3 py-1 bg-cyan-500 text-white" : "px-3 py-1 bg-slate-100 hover:bg-slate-200" %>
  <% (1..12).each do |m| %>
    <%= link_to Date::ABBR_MONTHNAMES[m], cash_flow_path(year: @selected_year, month: m),
        class: @selected_month == m ? "px-3 py-1 bg-cyan-500 text-white" : "px-3 py-1 bg-slate-100 hover:bg-slate-200" %>
  <% end %>
</div>

<%# Summary Card (refined) %>
<div class="bg-white dark:bg-slate-800 p-6 mb-6">
  <div class="flex items-center justify-between text-sm mb-2">
    <span class="<%= ui_text_muted_class %>">
      <%= @selected_month ? Date::MONTHNAMES[@selected_month] : "Full Year" %> <%= @selected_year %>
    </span>
  </div>
  
  <div class="flex items-center gap-4 text-lg">
    <span class="<%= ui_positive_class %>">+<%= format_currency(@period_totals[:income], precision: 0) %></span>
    <span class="<%= ui_text_subtle_class %>">−</span>
    <span class="<%= ui_negative_class %>"><%= format_currency(@period_totals[:expenses], precision: 0) %></span>
    <span class="<%= ui_text_subtle_class %>">=</span>
    <span class="font-bold <%= @period_totals[:net] >= 0 ? ui_positive_class : ui_negative_class %>">
      <%= @period_totals[:net] >= 0 ? '+' : '' %><%= format_currency(@period_totals[:net], precision: 0) %>
    </span>
    <span class="<%= ui_text_muted_class %>">
      (<%= @period_totals[:saving_rate] %>% <%= @period_totals[:net] >= 0 ? 'saved' : 'deficit' %>)
    </span>
  </div>
  
  <%# Visual bar %>
  <% if @period_totals[:income] > 0 %>
    <% expense_pct = [(@period_totals[:expenses].to_f / @period_totals[:income] * 100).round, 100].min %>
    <% saved_pct = [100 - expense_pct, 0].max %>
    <div class="mt-4 h-3 flex overflow-hidden">
      <div style="width: <%= expense_pct %>%;" class="bg-rose-300 dark:bg-rose-500/50"></div>
      <div style="width: <%= saved_pct %>%;" class="bg-emerald-300 dark:bg-emerald-500/50"></div>
    </div>
    <div class="flex justify-between text-xs mt-1">
      <span class="<%= ui_text_muted_class %>">Spent <%= expense_pct %>%</span>
      <span class="<%= ui_text_muted_class %>">Saved <%= saved_pct %>%</span>
    </div>
  <% end %>
</div>

<%# Nested Donut Chart %>
<div class="bg-white dark:bg-slate-800 p-6 mb-6">
  <h3 class="<%= ui_subheading_class %> mb-4">
    <%= @selected_month ? Date::MONTHNAMES[@selected_month] : @selected_year %> Breakdown
  </h3>
  
  <div class="flex flex-col md:flex-row items-center gap-8">
    <%# SVG Donut %>
    <% chart_data = build_nested_donut_data(@income_by_category, @expense_by_category, @period_totals) %>
    <svg width="220" height="220" viewBox="0 0 220 220" class="flex-shrink-0">
      <%# Outer ring (expenses + savings) - r=90, stroke-width=30 %>
      <% circumference_outer = 2 * Math::PI * 90 %>
      <% offset_outer = 0 %>
      <% chart_data[:expenses].each do |segment| %>
        <% arc_length = (segment[:pct] / 100.0 * circumference_outer) %>
        <circle cx="110" cy="110" r="90" fill="none"
                stroke="<%= segment[:color] %>" 
                stroke-width="30"
                stroke-dasharray="<%= arc_length %> <%= circumference_outer %>"
                stroke-dashoffset="<%= circumference_outer / 4 - offset_outer %>"
                class="transition-all duration-300">
          <title><%= segment[:name] %>: <%= format_currency(segment[:value], precision: 0) %> (<%= segment[:pct] %>%)</title>
        </circle>
        <% offset_outer += arc_length %>
      <% end %>
      
      <%# Inner ring (income) - r=55, stroke-width=25 %>
      <% circumference_inner = 2 * Math::PI * 55 %>
      <% offset_inner = 0 %>
      <% chart_data[:income].each do |segment| %>
        <% arc_length = (segment[:pct] / 100.0 * circumference_inner) %>
        <circle cx="110" cy="110" r="55" fill="none"
                stroke="<%= segment[:color] %>" 
                stroke-width="25"
                stroke-dasharray="<%= arc_length %> <%= circumference_inner %>"
                stroke-dashoffset="<%= circumference_inner / 4 - offset_inner %>"
                class="transition-all duration-300">
          <title><%= segment[:name] %>: <%= format_currency(segment[:value], precision: 0) %> (<%= segment[:pct] %>%)</title>
        </circle>
        <% offset_inner += arc_length %>
      <% end %>
      
      <%# Center text %>
      <text x="110" y="105" text-anchor="middle" 
            class="text-lg font-bold <%= @period_totals[:net] >= 0 ? 'fill-emerald-600' : 'fill-rose-500' %>">
        <%= @period_totals[:net] >= 0 ? '+' : '' %><%= number_to_currency(@period_totals[:net], unit: '', precision: 0, delimiter: "'") %>
      </text>
      <text x="110" y="125" text-anchor="middle" class="text-xs fill-slate-400">
        <%= @period_totals[:net] >= 0 ? 'Net Savings' : 'Deficit' %>
      </text>
    </svg>
    
    <%# Legend %>
    <div class="flex-1 grid grid-cols-2 gap-x-8 gap-y-1 text-sm">
      <div>
        <h4 class="font-medium <%= ui_text_class %> mb-2">Income</h4>
        <% chart_data[:income].each do |item| %>
          <div class="flex items-center justify-between py-0.5">
            <div class="flex items-center">
              <span class="w-3 h-3 mr-2" style="background: <%= item[:color] %>"></span>
              <span class="<%= ui_text_muted_class %>"><%= item[:name] %></span>
            </div>
            <span class="<%= ui_text_class %> tabular-nums"><%= item[:pct] %>%</span>
          </div>
        <% end %>
      </div>
      <div>
        <h4 class="font-medium <%= ui_text_class %> mb-2">Expenses</h4>
        <% chart_data[:expenses].each do |item| %>
          <div class="flex items-center justify-between py-0.5">
            <div class="flex items-center">
              <span class="w-3 h-3 mr-2" style="background: <%= item[:color] %>"></span>
              <span class="<%= ui_text_muted_class %> <%= item[:name] == 'Savings' ? 'font-medium' : '' %>"><%= item[:name] %></span>
            </div>
            <span class="<%= ui_text_class %> tabular-nums"><%= item[:pct] %>%</span>
          </div>
        <% end %>
      </div>
    </div>
  </div>
</div>

<%# Monthly table - highlight selected month %>
...existing table with @selected_month highlighting...

<%# Budgets - use @budget_year and @budget_month %>
...existing budgets section with updated context...
```

## Page Layout

```
┌─────────────────────────────────────────────────────────────────┐
│  ← 2024          2025          2026 →                           │
├─────────────────────────────────────────────────────────────────┤
│  Year │ Jan │ Feb │ Mar │ Apr │ May │ Jun │ Jul │ Aug │...│ Dec │
├─────────────────────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  March 2025                                               │  │
│  │  +$10,500 − $8,200 = +$2,300 (22% saved)                 │  │
│  │  ████████████████████████████░░░░░░░░░░░                  │  │
│  │  ← Spent 78% ─────────────── │ ─── Saved 22% →           │  │
│  └───────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  March 2025 Breakdown                                     │  │
│  │                                                           │  │
│  │      ┌──────────────────┐     INCOME                      │  │
│  │      │  ┌────────────┐  │     ● Salary     85%            │  │
│  │      │  │            │  │     ● Rental     12%            │  │
│  │      │  │  +$2,300   │  │     ● Other       3%            │  │
│  │      │  │  Savings   │  │                                 │  │
│  │      │  └────────────┘  │     EXPENSES                    │  │
│  │      │    (income)      │     ● Housing    35%            │  │
│  │      └──────────────────┘     ● Food       18%            │  │
│  │       (expenses+savings)      ● Transport  12%            │  │
│  │                               ● ...                       │  │
│  │                               ● Savings    22%            │  │
│  └───────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│  Monthly Breakdown Table (12 rows)                              │
│  - March row highlighted if month=3                             │
├─────────────────────────────────────────────────────────────────┤
│  Budgets (Monthly: March | Yearly: 2025)                        │
└─────────────────────────────────────────────────────────────────┘
```

## Testing Considerations

- [ ] Year navigation with edge cases (first/last year with data)
- [ ] Month filter showing correct category breakdown
- [ ] Donut chart with no transactions (empty state)
- [ ] Donut chart with single income category
- [ ] Donut chart showing deficit (no savings slice)
- [ ] Budget context updates correctly for selected period
- [ ] Seeds create varied monthly net savings
- [ ] Future months in current year show as grayed/empty

## Implementation Order

1. **Seeds** - Add varied monthly profiles (can test independently)
2. **Controller** - Add year/month params, new calculation methods
3. **Helper** - Add nested donut chart data builder
4. **View - Navigation** - Year prev/next, month filter tabs
5. **View - Summary Card** - Refined single-card design
6. **View - Donut Chart** - Nested SVG with legend
7. **View - Table** - Highlight selected month
8. **View - Budgets** - Use selected year/month context
9. **SPEC.md** - Document new features
10. **Tests** - Run `rails test` and `rubocop`

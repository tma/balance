# Annual Cash Flow Projection

## Problem
Users have months or years of transaction data but no way to answer the question: "What does a typical year of my finances look like?" The existing cash flow view shows actual historical data per calendar year, but doesn't synthesize all available data into a single annualized projection.

## Proposed Solution
Add a new **"Projected"** tab on the cash flow page that computes annualized income and expense projections using **all available transaction history**. The projection shows:

1. **Annual totals** — projected yearly income, expenses, net, and saving rate
2. **Category-level breakdown** — projected annual spend/income per category
3. **Confidence indicators** — flags categories with high variability (unreliable projections)

### How the Projection Works

1. **Data scope:** All transactions in the database (no date filter)
2. **Active months:** Count the number of distinct months that have at least one transaction (not calendar months since account creation — only months with actual data)
3. **Monthly average per category:** Sum all `amount_in_default_currency` for each category, divide by active months
4. **Annualized figure:** Monthly average × 12
5. **Variability:** Calculate coefficient of variation (CV = stddev / mean) across monthly totals per category. Flag categories where CV > 0.5 (50%) as "Variable" and CV > 1.0 as "Highly Variable"

### Why "active months" instead of calendar months?
If a user has 3 months of data in 2024 and 6 months in 2025, using the 9 active months gives a more accurate monthly average than dividing by the 15-month calendar span (which would undercount due to missing data).

## UI Design

### Tab Integration
The cash flow page currently has a "Year" button and month tabs (Jan-Dec) with year navigation arrows. We add a **"Projected"** tab button to the left of the "Year" button, visually distinct (e.g., dashed border or different accent color to signal it's synthetic/computed data, not historical).

When "Projected" is active:
- Year navigation arrows are hidden (projection is timeless — uses all data)
- Month tabs are hidden (projection shows a full virtual year)
- URL: `/cash-flow?view=projected`

### Layout (when Projected tab is active)

#### 1. Summary Card (top)
Same structure as the existing period summary — donut showing saving rate:
- **Projected Annual Income:** Monthly avg × 12
- **Projected Annual Expenses:** Monthly avg × 12
- **Projected Annual Net:** Income - Expenses
- **Projected Saving Rate:** Net / Income × 100
- Subtitle: "Based on N months of data (M transactions)"

#### 2. Category Breakdown Donut (top, beside summary)
Same nested donut as existing, but with projected annual values.

#### 3. Income Categories Table
Same layout as existing income table:
| Income Category | % | Projected Annual |
With an additional **confidence badge** column.

#### 4. Expense Categories Table
Same layout as existing expense table:
| Expense Category | Budget Bar | Annual Budget | % | Projected Annual | Confidence |

**Budget comparison:** For expense categories with yearly budgets, show the budget bar comparing projected annual spend vs yearly budget. For categories with only monthly budgets, multiply the monthly budget by 12 for comparison.

**Confidence badges:**
- No badge = CV ≤ 0.5 (consistent spending, reliable projection)
- `Variable` (amber badge) = 0.5 < CV ≤ 1.0
- `Erratic` (red badge) = CV > 1.0

#### 5. Monthly Average Bar Chart (bottom, optional/stretch)
Instead of showing 12 actual months, show a single bar pair: avg monthly income vs avg monthly expenses, with whiskers or a range indicator showing min/max months. This gives a visual sense of the "typical month."

## Implementation

### Files to Modify

#### Routes (`config/routes.rb`)
No new route needed. The existing `cash_flow` action handles the `view=projected` param.

#### Controller (`app/controllers/dashboard_controller.rb`)
Add to `cash_flow` action:
```ruby
if params[:view] == "projected"
  @projection = calculate_annual_projection
  render "dashboard/cash_flow_projected"
  return
end
```

Add private methods:
```ruby
def calculate_annual_projection
  # Count active months (distinct year-month combos with transactions)
  active_months = Transaction.distinct.count("strftime('%Y-%m', date)")
  total_transactions = Transaction.count
  
  return nil if active_months == 0
  
  # Category-level monthly averages with variability
  categories_data = calculate_projected_categories(active_months)
  
  # Separate by type
  income_categories = categories_data.select { |c| c[:category_type] == "income" }
  expense_categories = categories_data.select { |c| c[:category_type] == "expense" }
  
  total_income = income_categories.sum { |c| c[:annual] }
  total_expenses = expense_categories.sum { |c| c[:annual] }
  net = total_income - total_expenses
  saving_rate = total_income > 0 ? ((net / total_income) * 100).round(1) : 0
  
  {
    active_months: active_months,
    total_transactions: total_transactions,
    date_range: {
      from: Transaction.minimum(:date),
      to: Transaction.maximum(:date)
    },
    income: total_income,
    expenses: total_expenses,
    net: net,
    saving_rate: saving_rate,
    income_categories: income_categories.sort_by { |c| -c[:annual] },
    expense_categories: expense_categories.sort_by { |c| -c[:annual] }
  }
end

def calculate_projected_categories(active_months)
  # Get monthly totals per category using signed amounts
  # Group by category_id and year-month
  monthly_by_category = Transaction.joins(:category)
    .group("transactions.category_id", "categories.name", "categories.category_type", 
           "strftime('%Y-%m', date)")
    .sum(Transaction.signed_amount_by_category_type_sql)
  
  # Reorganize: { category_id => { name:, type:, monthly_totals: [amounts] } }
  categories = {}
  monthly_by_category.each do |(cat_id, cat_name, cat_type, year_month), amount|
    categories[cat_id] ||= { 
      id: cat_id, name: cat_name, category_type: cat_type, 
      monthly_totals: Hash.new(0) 
    }
    categories[cat_id][:monthly_totals][year_month] = amount
  end
  
  categories.values.map do |cat|
    totals = cat[:monthly_totals].values
    # Pad with zeros for active months without this category
    while totals.size < active_months
      totals << 0
    end
    
    total = totals.sum
    monthly_avg = total.to_f / active_months
    annual = monthly_avg * 12
    
    # Coefficient of variation
    mean = monthly_avg
    if mean != 0 && totals.size > 1
      variance = totals.sum { |t| (t - mean) ** 2 } / totals.size.to_f
      stddev = Math.sqrt(variance)
      cv = (stddev / mean.abs).round(2)
    else
      cv = 0
    end
    
    confidence = if cv <= 0.5
      :stable
    elsif cv <= 1.0
      :variable
    else
      :erratic
    end
    
    {
      id: cat[:id],
      name: cat[:name],
      category_type: cat[:category_type],
      monthly_avg: monthly_avg.round(2),
      annual: annual.round(2),
      cv: cv,
      confidence: confidence,
      months_with_data: cat[:monthly_totals].size,
      total: total
    }
  end
end
```

#### New View (`app/views/dashboard/cash_flow_projected.html.erb`)
New template for the projected view. Reuses existing UI patterns (card classes, table classes, donut chart, breadcrumbs). Contains:
- Breadcrumbs: Reports > Cash Flow > Projected
- Tab bar with "Projected" highlighted (no month/year navigation)
- Summary donut (reuse existing saving rate donut pattern)
- Category donut (reuse nested donut pattern)
- Income categories table
- Expense categories table with budget comparison and confidence badges

#### Helper Updates (`app/helpers/dashboard_helper.rb`)
May need minor additions for confidence badge rendering, but can likely be done inline or with a small helper method.

### Testing

#### Model/Controller Test
```ruby
# test/controllers/dashboard_controller_test.rb
test "cash_flow with projected view" do
  get cash_flow_path(view: "projected")
  assert_response :success
end

test "projected view with no transactions shows empty state" do
  Transaction.delete_all
  get cash_flow_path(view: "projected")
  assert_response :success
end

test "projected calculation uses all available data" do
  # Create transactions across multiple months
  # Verify annualized figures are correct
end
```

### Edge Cases
1. **No transactions:** Show empty state with message "Import some transactions to see projections"
2. **Single month of data:** Projection works but confidence is low across the board — show a note
3. **Categories with only 1-2 occurrences:** Will show as "Erratic" via CV, which is correct
4. **Multi-currency:** Use `amount_in_default_currency` throughout (already converted at import time)
5. **Refunds:** Handled via `signed_amount_by_category_type_sql` — refunds on expense categories reduce the expense projection

### Not in Scope (possible future enhancements)
- Configurable lookback period (last 6/12/24 months)
- Seasonal adjustment (weight recent months more heavily)
- Trend lines (are expenses increasing year-over-year?)
- Export projection as PDF/CSV

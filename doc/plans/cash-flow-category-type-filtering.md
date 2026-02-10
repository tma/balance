# Cash Flow: Fix Category Type Filtering

## Problem

On the cash flow page, expense categories that have positive (income-type) transactions
appear in the income table. For example, a refund from a grocery store categorized under
"Groceries" (an expense category) shows up in the income categories table because the
transaction has `transaction_type = 'income'`.

The current code filters by `Transaction.income` / `Transaction.expense` (which filters on
`transaction_type`), but the correct behavior is to group by **category type** instead.

## Desired Behavior

- Income table shows only categories where `category.category_type = 'income'`
- Expense table shows only categories where `category.category_type = 'expense'`
- Income-type transactions on expense categories reduce the net spent amount (refunds)
- Expense-type transactions on income categories reduce the net earned amount
- Summary totals (total income, total expenses, net, saving rate) also use category-type
  based grouping with signed amounts

## Sign Convention

Amounts are always stored as positive values. The sign is determined by `transaction_type`.
When grouping by category type:

- **Expense categories**: `expense` transactions add to spent; `income` transactions subtract
  ```sql
  SUM(CASE WHEN transaction_type='expense' THEN amount ELSE -amount END)
  ```
- **Income categories**: `income` transactions add to earned; `expense` transactions subtract
  ```sql
  SUM(CASE WHEN transaction_type='income' THEN amount ELSE -amount END)
  ```

## Methods to Change in `DashboardController`

1. **`calculate_monthly_data_for_year`** (line 195) - monthly bar chart + table
2. **`calculate_year_totals`** (line 218) - year summary
3. **`calculate_period_totals`** (line 227) - period summary (month or year)
4. **`enrich_monthly_data_with_averages`** (line 245) - trailing average + anomaly
5. **`calculate_category_breakdown`** (line 294) - donut chart
6. **`build_category_spending`** (line 308) - expense categories table
7. **`build_income_category_spending`** (line 349) - income categories table
8. **`calculate_monthly_data`** (line 165) - used by home dashboard

## Implementation

Add a helper method `signed_sum_by_category_type` that joins transactions with categories,
groups by category type, and returns signed sums. Then refactor all the above methods to
use it instead of `Transaction.income` / `Transaction.expense` scopes.

# Cash Flow Category Table: Percentages & Income Categories

## Problem
1. The category breakdown donut legend shows percentage per category, but the category table below does not show these percentages.
2. The category table only shows expense categories. Income categories are missing entirely.
3. The category table is sorted alphabetically, but should be sorted by percentage (highest first).

## Proposed Solution

### 1. Add percentage column to expense category table
- Compute each expense category's percentage of total expenses (amount / total_expenses * 100), rounded to whole numbers.
- Add a "%" column to the table, displayed before the "Spent" column.
- Sort categories by percentage descending (highest spending categories first).

### 2. Add income categories table
- Build an `@income_category_spending` variable in the controller (similar to `@category_spending` but for income).
- Display income categories in a separate table above the expense table with the same structure: Category, %, Earned columns.
- Income table does not need budget/progress columns since budgets are expense-only.
- Sort by percentage descending.

### Files to Modify
- `app/controllers/dashboard_controller.rb` — add `build_income_category_spending` method and call it; compute total expenses/income for percentage calculation
- `app/views/dashboard/cash_flow.html.erb` — add % column to expense table, add income table, change sort order

### Considerations
- Percentages should be rounded to whole integers (matching the donut legend behavior).
- The percentage values represent share of total expenses (or total income), not budget usage.
- Budget progress bar column stays as-is (it shows budget % used, which is a different metric).

## Outcome (Implemented)

### Column layout

**Income table** (only rendered when income data exists):
| Income (name) | % | Earned |

**Expense table**:
| Expenses (name) | Progress bar | Budget | % | Spent |

- Column headers use "Income" / "Expenses" instead of "Category".
- The % column header is intentionally blank (values still show, e.g. "42%").
- Fixed widths: 60px for % column, 120px for amount columns (Budget, Spent, Earned).
- Progress bar column has `min-width: 200px`.
- Amount and % cells use `tabular-nums whitespace-nowrap`.

### Sorting
Both tables sort by percentage descending with a tiebreaker on amount descending:
- Expense: `[-pct, -spent]`
- Income: `[-pct, -earned]`

### Controller changes
- `build_category_spending`: added `pct` field; changed sort from alphabetical to `[-pct, -spent]`.
- New `build_income_category_spending` method returning `{ category:, earned:, pct: }` structs.
- `cash_flow` action sets `@income_category_spending`.

### Known tradeoffs
- Rounded percentages may not sum to exactly 100% (unlike the donut chart helper which adjusts the largest segment). Accepted as cosmetic.

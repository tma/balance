# Import Coverage Gap Detection

## Problem Statement

When importing bank statements, there's no way to see which accounts have complete transaction history and which have date range gaps. Imports don't follow calendar months - they typically cover irregular periods like "Jan 15 → Feb 15". Users need visibility into which date ranges are missing data.

## Requirements

1. Show coverage gaps on the imports index page
2. Use transaction dates to determine coverage (not calendar months)
3. Detect exact date range gaps between imports
4. Only flag gaps greater than 7 days (small gaps from statement overlaps are normal)
5. Track all accounts that have at least one completed import
6. Coverage should only consider the past (not flag future dates as missing)

## Design

### Coverage Algorithm

For each account with completed imports:

1. **Get all coverage periods**: For each "done" import, get the date range from min to max transaction date
2. **Merge overlapping periods**: Combine periods that overlap or are adjacent (within 7 days)
3. **Find gaps**: Identify date ranges between merged periods that are > 7 days
4. **Limit to past**: Only show gaps for dates before today

Example:
```
Import A: Jan 15 → Feb 15
Import B: Feb 14 → Mar 14  
Import C: Apr 1 → May 1

Merged: [Jan 15 → Mar 14], [Apr 1 → May 1]
Gap: Mar 15 → Mar 31 (17 days) ← FLAG THIS
```

### Visual Design

Add a collapsible "Coverage" section at the top of imports index:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ ▼ Coverage                                                              │
├─────────────────────────────────────────────────────────────────────────┤
│ Checking Account                   Jan 15, 2024 → Jan 28, 2026         │
│   ⚠ Gap: Mar 15 - Mar 31, 2025 (17 days)                               │
│                                                                         │
│ Savings Account                    Jun 3, 2024 → Dec 28, 2025          │
│   ✓ Complete                                                            │
│                                                                         │
│ Credit Card                        Jan 1, 2025 → Jan 15, 2026          │
│   ⚠ Gap: Sep 20 - Oct 5, 2025 (15 days)                                │
│   ⚠ Gap: Nov 1 - Nov 30, 2025 (30 days)                                │
└─────────────────────────────────────────────────────────────────────────┘
```

### Data Model

**No database changes required.** Coverage is computed from existing transaction data.

However, we should add a method to cache/memoize coverage computation since it could be expensive for accounts with many imports.

## Implementation

### 1. Account Model - Coverage Computation

Add `app/models/concerns/account_coverage.rb`:

```ruby
module AccountCoverage
  extend ActiveSupport::Concern

  GAP_THRESHOLD_DAYS = 7

  def coverage_analysis
    return nil unless imports.done.exists?

    # Get date ranges from each done import's transactions
    periods = imports.done.includes(:transactions).filter_map do |import|
      dates = import.transactions.pluck(:date)
      next if dates.empty?
      { start: dates.min, end: dates.max }
    end

    return nil if periods.empty?

    # Sort by start date
    periods.sort_by! { |p| p[:start] }

    # Merge overlapping/adjacent periods
    merged = merge_periods(periods)

    # Find gaps > threshold
    gaps = find_gaps(merged)

    {
      account: self,
      first_date: merged.first[:start],
      last_date: merged.last[:end],
      periods: merged,
      gaps: gaps,
      complete?: gaps.empty?
    }
  end

  private

  def merge_periods(periods)
    return [] if periods.empty?

    merged = [periods.first.dup]

    periods[1..].each do |period|
      last = merged.last
      # If this period overlaps or is within GAP_THRESHOLD_DAYS of last, merge them
      if period[:start] <= last[:end] + GAP_THRESHOLD_DAYS.days
        last[:end] = [last[:end], period[:end]].max
      else
        merged << period.dup
      end
    end

    merged
  end

  def find_gaps(merged_periods)
    return [] if merged_periods.size < 2

    gaps = []
    today = Date.current

    merged_periods.each_cons(2) do |period_a, period_b|
      gap_start = period_a[:end] + 1.day
      gap_end = period_b[:start] - 1.day
      gap_days = (gap_end - gap_start).to_i + 1

      # Only flag past gaps > threshold
      next if gap_days <= GAP_THRESHOLD_DAYS
      next if gap_start > today

      gaps << {
        start: gap_start,
        end: [gap_end, today].min,
        days: gap_days
      }
    end

    gaps
  end
end
```

Include in Account model:
```ruby
# app/models/account.rb
include AccountCoverage
```

### 2. Imports Controller

Add coverage data to index action:

```ruby
# app/controllers/imports_controller.rb
def index
  # ... existing code ...

  # Coverage analysis for accounts with done imports
  accounts_with_imports = Account.active
    .joins(:imports)
    .where(imports: { status: 'done' })
    .distinct
    .includes(imports: :transactions)

  @account_coverage = accounts_with_imports.filter_map(&:coverage_analysis)
    .sort_by { |c| c[:complete?] ? 1 : 0 }  # Show incomplete first
end
```

### 3. View - Coverage Section

Add to `app/views/imports/index.html.erb` above year navigation:

```erb
<% if @account_coverage.any? %>
  <div class="<%= ui_card_class %> mb-4" data-controller="collapsible">
    <div class="px-4 py-3 cursor-pointer flex items-center justify-between hover:bg-slate-50 dark:hover:bg-slate-700/50 transition"
         data-action="click->collapsible#toggle">
      <div class="flex items-center gap-2">
        <span data-collapsible-target="icon" class="<%= ui_text_muted_class %> text-xs">▶</span>
        <h2 class="text-sm font-medium <%= ui_text_class %>">Coverage</h2>
        <% gaps_count = @account_coverage.count { |c| !c[:complete?] } %>
        <% if gaps_count > 0 %>
          <span class="text-xs px-1.5 py-0.5 rounded bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-400">
            <%= gaps_count %> account<%= gaps_count == 1 ? '' : 's' %> with gaps
          </span>
        <% end %>
      </div>
    </div>
    
    <div data-collapsible-target="content" class="hidden">
      <div class="border-t border-slate-200 dark:border-slate-700">
        <% @account_coverage.each do |coverage| %>
          <div class="px-4 py-2.5 border-b last:border-b-0 border-slate-100 dark:border-slate-700/50">
            <div class="flex items-center justify-between">
              <span class="<%= ui_text_class %> font-medium text-sm">
                <%= coverage[:account].name %>
              </span>
              <span class="<%= ui_text_muted_class %> text-xs">
                <%= coverage[:first_date].strftime("%b %-d, %Y") %> → 
                <%= coverage[:last_date].strftime("%b %-d, %Y") %>
                <% if coverage[:complete?] %>
                  <span class="text-emerald-600 dark:text-emerald-400 ml-1">✓</span>
                <% end %>
              </span>
            </div>
            
            <% if coverage[:gaps].any? %>
              <div class="mt-1.5 space-y-0.5">
                <% coverage[:gaps].each do |gap| %>
                  <div class="text-xs text-amber-600 dark:text-amber-400">
                    ⚠ Gap: <%= gap[:start].strftime("%b %-d") %> - <%= gap[:end].strftime("%b %-d, %Y") %>
                    <span class="<%= ui_text_subtle_class %>">(<%= gap[:days] %> days)</span>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
  </div>
<% end %>
```

### 4. Seed Data - Demonstrate Coverage Gaps

Update `db/seeds.rb` to create imports with deliberate gaps for demonstration:

**New CSV files to create** (in `test/fixtures/files/csv_samples/`):

1. `main_checking_oct_2025.csv` - Oct 15 → Nov 14, 2025
2. `main_checking_dec_2025.csv` - Dec 15, 2025 → Jan 14, 2026
3. `visa_sep_2025.csv` - Sep 1 → Sep 30, 2025
4. `visa_dec_2025.csv` - Dec 1 → Dec 31, 2025

This creates:
- **Main Checking**: Gap from Nov 15 - Dec 14, 2025 (30 days)
- **Visa Credit Card**: Gap from Oct 1 - Nov 30, 2025 (61 days)
- **Other accounts**: Complete coverage (existing CSVs)

**Seed data changes:**

```ruby
# After existing CSV imports, add statement-like imports with gaps:

puts "  Creating imports with coverage gaps for demo..."

# Helper to create a simple CSV with transactions in a date range
def generate_statement_csv(start_date, end_date, transactions_per_week: 5)
  csv_lines = ["Date,Description,Amount"]
  
  current = start_date
  while current <= end_date
    # Add some transactions for this day
    if rand < 0.7  # 70% chance of transaction on any day
      amount = [-50, -25, -100, -15, 500, -75, -200].sample + rand(50)
      description = ["GROCERY STORE", "GAS STATION", "RESTAURANT", "ONLINE PURCHASE", "DEPOSIT", "UTILITY BILL"].sample
      csv_lines << "#{current.strftime('%Y-%m-%d')},#{description},#{amount.round(2)}"
    end
    current += 1.day
  end
  
  csv_lines.join("\n")
end

# Main Checking - Create gap from Nov 15 - Dec 14
oct_csv = generate_statement_csv(Date.new(2025, 10, 15), Date.new(2025, 11, 14))
import = Import.create!(
  account: accounts[:main_checking],
  original_filename: "statement_oct_2025.csv",
  file_content_type: "text/csv",
  file_data: oct_csv,
  status: "done"
)
# Create transactions directly (skip extraction for speed)
# ... similar pattern as existing seed data

dec_csv = generate_statement_csv(Date.new(2025, 12, 15), Date.new(2026, 1, 14))
import = Import.create!(
  account: accounts[:main_checking],
  original_filename: "statement_dec_2025.csv",
  # ...
)

# Visa - Create larger gap from Oct 1 - Nov 30
sep_csv = generate_statement_csv(Date.new(2025, 9, 1), Date.new(2025, 9, 30))
# ...

dec_csv = generate_statement_csv(Date.new(2025, 12, 1), Date.new(2025, 12, 31))
# ...
```

## Files to Create/Modify

| File | Changes |
|------|---------|
| `app/models/concerns/account_coverage.rb` | **New file** - Coverage analysis concern |
| `app/models/account.rb` | Include `AccountCoverage` concern |
| `app/controllers/imports_controller.rb` | Add `@account_coverage` in index action |
| `app/views/imports/index.html.erb` | Add coverage section |
| `test/models/account_coverage_test.rb` | **New file** - Tests for coverage logic |
| `db/seeds.rb` | Add imports with deliberate gaps for demo |

## Test Cases

1. **No imports**: Account not shown in coverage
2. **Single import**: Shows as complete (no gaps possible)
3. **Adjacent imports (within 7 days)**: No gap flagged
4. **Imports with 8+ day gap**: Gap flagged
5. **Future dates**: Not flagged as missing
6. **Large CSV import**: Should work correctly with 1+ year of data
7. **Overlapping imports**: Properly merged, no false gaps

## Edge Cases

- **Import with no transactions**: Skipped in coverage analysis
- **Account with only manual transactions**: Not shown (no imports)
- **Archived accounts**: Not shown in coverage (only active accounts)
- **Gap at the end (no recent imports)**: Only flagged if gap is in the past

## Implementation Steps

1. Create feature branch: `git checkout -b feature/import-coverage-gaps`
2. Create `app/models/concerns/account_coverage.rb`
3. Include concern in `app/models/account.rb`
4. Update `app/controllers/imports_controller.rb` index action
5. Update `app/views/imports/index.html.erb` with coverage section
6. Create `test/models/account_coverage_test.rb` with unit tests
7. Update `db/seeds.rb` to create imports with gaps
8. Run tests: `rails test`
9. Run linter: `rubocop`
10. Reset database and test visually: `rails db:reset`

## Future Enhancements (Out of Scope)

1. Persist coverage periods on imports for better performance
2. Extract and store statement period from PDFs during import
3. Visual timeline/calendar view of coverage
4. Per-account toggle to exclude from coverage tracking

# Cost of Living Projection

## Problem

The projected cash flow view estimates a typical year of all income and expenses,
but it does not answer how much income is required to cover the user's minimum
cost of living. Expense categories alone are not precise enough for this purpose:
groceries are essential but variable, while some subscriptions are recurring but
discretionary. A category can also contain a mixture of both.

## Proposed Solution

Add a **Cost of Living** view beside the existing Projected view. It separates:

1. **Fixed commitments** - confirmed essential recurring expense streams.
2. **Essential variable costs** - non-recurring spending from categories or
   merchant rules marked essential.
3. **Cost of living baseline** - fixed commitments plus essential variable costs,
   shown as monthly and annual amounts.

The feature uses category defaults for broad classification and merchant-level
profiles for exceptions. Automated classifications are suggestions until the user
confirms them.

## Classification Model

### Category Defaults

Expense categories receive an `essentiality` value:

- `essential` - included by default in the baseline.
- `discretionary` - excluded by default.
- `mixed` - excluded unless a matching expense profile is confirmed as essential.
- `excluded` - transfers, savings, and other non-cost cash movements.

No classification is inferred from category names at report time. Seeds may
provide initial suggestions, but the values remain editable in Admin.

### Expense Profiles

An expense profile represents a stable merchant or bill stream and can override
its category default. It stores:

- Category and word-boundary merchant pattern.
- Essentiality (`essential` or `discretionary`).
- Recurrence status and optional cadence (`monthly`, `quarterly`,
  `semiannual`, or `annual`).
- Source (`manual` or `learned`), confidence, review status, and active status.

Only confirmed, active learned profiles affect the Cost of Living projection.
Manual profiles are confirmed when created. Dismissed or inactive profiles do not
affect the projection.

## Review Workflow

The user never reviews transactions one by one. The setup flow has two short
stages:

1. **Category defaults** - review each expense category once and accept or change
   its suggested essentiality. This covers variable spending such as groceries
   without requiring merchant-level decisions.
2. **Recurring expense streams** - review grouped merchant/category profiles, not
   individual transactions. For example, 24 Netflix transactions become one row
   showing the merchant, category, transaction count, date range, typical amount,
   detected cadence, suggested essentiality, confidence, and annual impact.

The recurring review queue includes repeated merchants with recurrence evidence
and prioritizes them by projected annual impact. One-time purchases do not create
review noise; they follow the confirmed category default unless the user manually
creates an override.

Each suggestion supports Confirm, Change, Dismiss, and viewing the underlying
transactions. The user may select multiple rows or explicitly accept all
high-confidence suggestions. Bulk acceptance is still an intentional confirmation
and must show the number of profiles and annual amount affected before applying.

After initial setup, only new or materially changed profiles return to the queue.
Previously confirmed profiles remain effective until disabled, while recency
checks flag likely canceled commitments for review.

## Ollama-Assisted Classification

Reuse the configured `OLLAMA_MODEL` and `OllamaService.generate_json`; do not add
another model dependency.

1. Normalize merchant names using the existing LLM merchant extraction approach.
2. Group completed expense transactions by category and normalized merchant.
3. Calculate recurrence evidence deterministically in Ruby from occurrence dates,
   interval consistency, amount consistency, and recency.
4. Give the model the merchant, category, transaction count, amount range, and
   recurrence summary. Ask it to suggest essentiality and resolve ambiguous
   fixed/recurring classifications in structured JSON.
5. Save the result as a learned suggestion for user review.

The model must not be the sole source of recurrence cadence. Deterministic evidence
is authoritative when sufficient history exists, and the user can always override
the result. Model failures leave the item unclassified and visible for manual
review; they do not produce a success-shaped default.

## Projection Calculation

Use completed months from the most recent 12-month lookback and reuse
`Transaction.detect_incomplete_months` to remove likely incomplete months.

### Fixed Commitments

For each confirmed active essential recurring profile:

- Match transactions with the profile's word-boundary pattern.
- Estimate the occurrence amount from the median of recent matching transactions.
- Annualize by cadence: monthly x 12, quarterly x 4, semiannual x 2, annual x 1.
- Allow manual cadence and amount confirmation when history is insufficient, such
  as a newly imported annual insurance payment.

### Essential Variable Costs

- Include expense transactions whose profile override or category default is
  essential.
- Exclude transactions already counted as fixed commitments.
- Aggregate by completed month, padding missing included months with zero.
- Use the median monthly total to limit distortion from one-time spikes.
- Annualize the monthly baseline by multiplying by 12.

The report must disclose its lookback period, excluded months, unreviewed
suggestions, and low-data conditions. It is a planning baseline, not a guarantee
or an AI-generated financial recommendation.

## User Interface

Add `/cash-flow?view=cost_of_living` and a **Cost of Living** tab.

The view contains:

- Minimum monthly income required.
- Annual cost of living baseline.
- Fixed commitments subtotal.
- Essential variable subtotal.
- Fixed commitment table with merchant, category, cadence, recent amount,
  annualized amount, confidence, and review state.
- Essential variable category breakdown.
- Review panel for learned and unclassified expense profiles.
- Links from each row to the matching transactions.

Admin category forms expose the category essentiality default. Profile review and
manual overrides use Turbo Frames and Turbo Streams. A guided initial setup first
reviews category defaults, then grouped recurring profiles ordered by annual
impact. It never presents a transaction-by-transaction classification queue.

## Anticipated Files

- `SPEC.md`
- `db/migrate/*_add_essentiality_to_categories.rb`
- `db/migrate/*_create_expense_profiles.rb`
- `app/models/category.rb`
- `app/models/expense_profile.rb`
- `app/services/expense_profile_detection_service.rb`
- `app/services/cost_of_living_projection_service.rb`
- `app/jobs/expense_profile_detection_job.rb`
- `app/controllers/dashboard_controller.rb`
- `app/controllers/expense_profiles_controller.rb`
- `app/views/dashboard/cash_flow*.html.erb`
- `app/views/dashboard/cash_flow_cost_of_living.html.erb`
- `app/views/expense_profiles/*`
- `app/views/admin/categories/*`
- `config/routes.rb`
- `db/seeds.rb`
- Relevant model, service, job, controller, and system tests

## Testing

- Category essentiality validation and defaults.
- Expense profile validation, confirmation, activation, pattern matching, and
  category override behavior.
- Deterministic cadence detection for monthly, quarterly, semiannual, annual,
  irregular, canceled, and insufficient-history streams.
- Structured Ollama response parsing and explicit failure behavior.
- Fixed commitment annualization and median occurrence amount.
- Essential variable monthly median, zero padding, refunds, incomplete months,
  lookback boundaries, and prevention of double counting.
- Empty, low-data, unreviewed, mixed-category, multi-currency, and inactive-profile
  report states.
- Cost of Living navigation, review actions, and transaction links.

## Considerations

- Savings and transfers are excluded rather than treated as living expenses.
- Refunds reduce costs using the existing signed amount helpers.
- All report amounts use `amount_in_default_currency`.
- The same merchant may require separate profiles in different categories.
- Recency checks are required so canceled subscriptions do not remain active.
- Classification prompts must send only the minimum transaction summary needed;
  the app remains local-first through Ollama.
- Run `rails categorization:benchmark` if shared categorization or merchant
  extraction behavior changes during implementation.

## Build Gate

Do not implement the feature until this plan and its corresponding `SPEC.md`
changes have received independent Grok and Opus reviews and their substantive
findings have been resolved.

# Cost of Living Projection - Review Revisions

## Status

This document resolves the independent Grok and Opus reviews of
`cost-of-living-projection.md`. Where the documents conflict, this revision and
the corresponding `SPEC.md` update are authoritative.

## Review Agreements

Both reviewers approved the core direction:

- Essentiality and recurrence are separate concepts.
- Category defaults handle broad variable spending.
- Merchant/category expense profiles handle exceptions and recurring streams.
- Users review grouped streams, never individual historical transactions.
- Ruby calculates recurrence evidence; the configured local Ollama model only
  suggests classifications.
- Learned suggestions do not affect the report until explicitly confirmed.

Both reviewers also found that the original 12-month median calculation could
silently omit annual and lumpy essential costs. They requested explicit detection
thresholds, lifecycle rules, model constraints, and failure disclosures.

## Resolved Projection Rules

### Time Windows

- The reporting window is the most recent 12 completed calendar months, limited
  to months covered by imported transaction history.
- Recurrence detection may inspect up to 36 completed months so annual and
  semiannual streams can provide more than one occurrence.
- Incomplete months are detected once from all transactions in the reporting
  window. The excluded-month list applies to amount aggregation and monthly
  displays only. Recurrence uses every eligible transaction in its 36-month
  window so incomplete imports do not distort cadence or overdue evidence.
- Months before the user's transaction coverage are never padded with zero.
- Reports based on fewer than six included completed months are shown as
  provisional rather than suppressed.

### Fixed Commitments

A fixed commitment is a confirmed essential merchant profile with a cadence and
confirmed occurrence amount. Interval regularity establishes recurrence; amount
variability is displayed but does not disqualify utilities or other variable bills.

Supported automatic cadence bands:

| Cadence | Median interval | Minimum occurrences |
| --- | --- | --- |
| Monthly | 25-35 days | 3 |
| Quarterly | 75-105 days | 3 |
| Semiannual | 150-215 days | 3 |
| Annual | 330-400 days | 2 |

High recurrence confidence requires at least three occurrences, interval
coefficient of variation at or below 0.15, and a current stream. Medium confidence
allows interval coefficient of variation up to 0.30; an annual stream with only
two occurrences is always medium. Lower-confidence candidates do not receive an
automatic cadence.

A stream is overdue when its last occurrence is older than 1.5 times the upper
bound of its cadence. Overdue confirmed streams remain in the baseline with their
confirmed values and receive a review flag until the user marks them inactive or
reconfirms them.

The detector uses expense-direction, non-refund occurrences with completed default
currency conversion. It sorts unique occurrence dates, calculates consecutive
intervals, and selects a cadence only when the median interval is inside a cadence
band and its minimum occurrence count is met. A stream is current when it is not
overdue. High confidence requires interval CV <= 0.15 and at least three
occurrences; medium requires interval CV <= 0.30, except that a two-occurrence
annual stream is always medium. Overdue candidates can be medium but never high.

On confirmation, the suggested amount defaults to the median of the latest three
expense-direction occurrences. Refunds do not count as recurrence events. The user
may override the amount and cadence, including for a single possible annual bill.
The annual value is confirmed amount multiplied by 12, 4, 2, or 1 for monthly,
quarterly, semiannual, or annual cadence.

Weekly and biweekly cadence detection is out of scope for v1. Such expenses remain
in essential variable spending unless the cadence set is expanded later.

### Essential Variable Costs

- Classification precedence is excluded category, longest matching confirmed
  merchant profile, then confirmed category default.
- Profiles in excluded categories never contribute to fixed commitments.
- Transactions assigned to fixed commitments are removed before variable
  aggregation, so no transaction is counted twice.
- Refunds and corrections use signed expense amounts.
- Annual essential variable cost equals signed variable expense total divided by
  included completed months, multiplied by 12.
- The median included-month value may be displayed as a supplementary "typical
  variable month" but does not drive the annual headline.
- A zero is used only when an included covered month genuinely has no matching
  essential variable spending.

This calculation preserves sparse healthcare, repairs, and other lumpy essentials
instead of reducing them to zero.

## Classification and Review Workload

Existing expense categories start unclassified. Once at least one category is
confirmed, the report renders a visibly incomplete baseline from confirmed
classifications only. Unclassified categories never contribute silently and their
annualized signed spending appears as unreviewed impact. Income categories remain
unclassified and are not eligible.

The second setup stage contains grouped merchant/category profiles ordered by
annual impact. Candidates come from existing Manual/Learned `CategoryPattern`
merchant patterns. Unmatched transactions are additionally grouped by exact
description without another LLM merchant-extraction call. An unmatched group with
fewer than two occurrences becomes a candidate only when its trailing-12-month
expense outflow is at least 1% of total trailing-12-month expense outflow; its
pattern is editable at confirmation.

A suggested profile enters the main review queue only when it has an automatic
cadence with medium or high confidence, or it is a material unmatched group in an
unclassified or mixed category. Confirmed profiles with review flags also enter
the queue. Other detected streams remain available without creating setup noise.

Bulk confirmation is available only for high-confidence deterministic recurrence
whose suggested essentiality agrees with a confirmed category default. Any profile
representing at least 5% of trailing annual expense outflow requires individual
review. The confirmation dialog shows affected profile count and annual amount.

The report discloses unreviewed annual impact and the percentage of classified
candidate spending so the headline cannot imply false completeness.

The 1% and 5% thresholds use positive expense-direction outflow in the 12-month
amount window after shared incomplete-month exclusions and pending currency
conversions. Refunds do not reduce the threshold denominator.

Unreviewed annual impact is the annualized signed spending from unclassified
categories plus queued suggestions not already represented by that category
amount. Recurring suggestions use their recent median occurrence amount and
detected cadence; no-cadence suggestions use their trailing-window signed spend.
Classified-spend percentage is classified eligible expense outflow divided by
total eligible expense outflow. Until it reaches 100%, the headline is explicitly
marked incomplete rather than hidden.

## Expense Profile Lifecycle

Profiles use one status: `suggested`, `confirmed`, `dismissed`, or `inactive`.

- Manual profiles are confirmed when created.
- Detection upserts one row per merchant pattern and category. It refreshes
  evidence from every non-dismissed profile's stored pattern even when its source
  CategoryPattern is later removed.
- An existing manual profile suppresses learned suggestion creation.
- Dismissed profiles stay dismissed until the user restores them.
- Inactive profiles were previously confirmed and no longer affect the baseline.
- Confirmed profiles remain effective with their confirmed values when new
  evidence differs; they receive review flags rather than silently changing.
- A material amount change is at least 20% from the confirmed amount. A detected
  cadence-band change or overdue stream is also reviewable.
- Suggested profiles may have null essentiality when Ollama is unavailable or
  invalid; confirmed profiles require essentiality. Material change compares the
  confirmed amount with the median of the latest three expense-direction matches.
- Detection never changes the status of confirmed, dismissed, or inactive
  profiles.

If multiple profile patterns match, the longest pattern wins, with the lowest
profile ID as the tie-break. Detection, confirmation, and reporting use the same
assignment. Each transaction can match at most one profile within its category.
Overlapping confirmed recurring profiles annualize only the winning longest
pattern; the shorter profile receives a superseded review flag.

## Ollama Contract

The same configured `OLLAMA_MODEL` is reused. `ExpenseProfileDetectionService`
consumes existing CategoryPattern groups and deterministic summaries, so merchant
normalization is not duplicated.

The model receives only candidate ID, merchant pattern, category, occurrence count,
date range, amount range, and deterministic recurrence summary. Batched output is:

```json
{
  "suggestions": [
    {
      "candidate_id": "candidate identifier",
      "essentiality": "essential",
      "recurrence_hint": "recurring"
    }
  ]
}
```

Allowed essentiality values are `essential`, `discretionary`, and `excluded`.
Allowed recurrence hints are `recurring`, `non_recurring`, and `unknown`. The
recurrence hint is advisory and never assigns cadence. Candidate IDs, uniqueness,
array membership, and enum values are validated. Missing, duplicate, malformed, or
out-of-set results leave the affected candidate unclassified. Model-provided
confidence is neither requested nor trusted.

Cost projection, category setup, deterministic detection, and manual profiles work
without Ollama. Unavailability is shown as suggestion status, not a report error.
The daily detection job runs after pattern extraction and after completed imports,
batches at most 10 candidates per call, and limits model classification to 50 new
or changed candidates per run.

## Data and Disclosure Requirements

Expense profiles persist their latest evidence snapshot: occurrence count, first
and last seen dates, median amount, amount coefficient of variation, interval
coefficient of variation, detected cadence, detection time, and confirmation time.
Confirmed recurring profiles also persist `confirmed_amount`.

Transactions missing `amount_in_default_currency` are excluded and counted in an
explicit pending-currency-conversion warning.

The "Minimum monthly income required" headline is defined as annual essential cost
divided by 12. Supporting copy states that it is an expense baseline, not a
tax-adjusted gross-income target or financial advice. The adjacent Projected view
uses all completed history, while Cost of Living intentionally displays a rolling
12-month spending window and up to 36 months of recurrence evidence.

## Existing Database Rollout

The schema upgrade is additive. `categories.essentiality` is nullable and the new
expense profile table starts empty, so existing financial data and reports are
unchanged. No migration or production seed guesses essentiality.

On first use, all existing expense categories appear as unclassified. The report
shows setup guidance until one is confirmed, then renders a visibly incomplete
baseline with unreviewed impact until classification is complete. Daily detection
populates grouped suggestions from existing history; **Refresh suggestions** runs
it immediately. Confirmed, dismissed, and inactive profile decisions survive
subsequent detection runs.

The feature remains manually usable without Ollama. Rollback removes only the
additive classification column and profile records, never transactions, budgets,
accounts, or categories.

## Required Acceptance Cases

- One confirmed CHF 1'200 annual insurance payment contributes CHF 1'200 annually.
- Sparse essential healthcare months contribute through the annualized mean and
  do not collapse to zero.
- A canceled subscription remains visible and included with a review flag until
  explicitly marked inactive.
- A variable monthly utility remains recurring despite high amount variation.
- Overlapping `AMAZON` and `AMAZON PRIME` profiles assign each transaction once to
  the longest match.
- Refunds reduce variable spending but do not create recurrence events.
- Fewer than six completed months produce a provisional headline.
- Missing exchange conversions and unreviewed annual impact are disclosed.
- Invalid or unavailable Ollama output does not block deterministic/manual use and
  never creates an effective classification.

## Build Gate

No feature code is to be implemented until Grok and Opus re-review the revised
`SPEC.md` and this resolution document without blocking findings.

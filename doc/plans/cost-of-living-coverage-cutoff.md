# Cost of Living Coverage Cutoff

## Problem

The Cost of Living report always ends at the previous calendar month. When
statement imports lag, that month may be only partially represented even if its
transaction count is high enough to avoid the existing low-count heuristic.

## Solution

Add a persistent Data Complete Through month with:

- An automatic default derived from active accounts that have transaction
  frequency tracking enabled.
- A manual month override, with an option to return to automatic mode.
- A visible reporting-window/freshness disclosure on Cost of Living.
- A shared effective cutoff used by both the 12-month projection and the
  36-month expense-profile evidence window.
- Profile detection queued whenever the override changes.

For each tracked account, its latest transaction plus its expected transaction
frequency defines the date through which coverage is supported. The automatic
cutoff is the latest fully completed calendar month supported by every tracked
account, capped at the most recently completed month. Accounts set to Not
Tracked do not constrain the cutoff.

## Files

- New `CostOfLivingSetting` model and migration
- New `CostOfLivingPeriodService`
- Projection and expense-profile detection services
- Cost of Living settings controller, route, and page controls
- Model, service, controller, projection, and detection tests
- `SPEC.md`

## Considerations

- Manual override is stored globally because the app is single-user.
- The override is normalized to the first day of its month and cannot point to
  the current or a future month.
- Existing low-count incomplete-month detection remains a secondary safeguard
  within the selected 12-month window.
- No transactions or import records are modified.

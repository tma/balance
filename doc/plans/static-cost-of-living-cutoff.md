# Static Cost of Living Cutoff

## Problem

The Data Complete Through selector behaves like report navigation and appears in
the URL, but currently persists global state and starts profile processing.
Viewing a different reporting window should not mutate expense-profile evidence
or create background work.

## Solution

- Make the cutoff selector a GET-only `through=YYYY-MM` report parameter.
- Use coverage-derived cutoff when `through` is absent.
- Keep Auto as a link back to the clean coverage-default URL.
- Remove the persisted cutoff setting, update endpoint, migration, and notices.
- Run profile detection only after imports or explicit Refresh Suggestions.
- When Refresh Suggestions is clicked from a manual view, pass that view's
  cutoff to the detection job explicitly.

## Files

- Cost of Living period, projection, detection job, controllers, routes, and view
- Related tests and `SPEC.md`
- Remove the unshipped CostOfLivingSetting model and migration

## Considerations

The selected report is recomputed from stored transactions and confirmed profile
decisions but causes no writes. Confirmed profile decisions are not historically
versioned; the cutoff controls transaction/evidence windows, not a point-in-time
snapshot of prior user decisions.

# Opus Implementation Review Fixes

## Problem

The Opus implementation review found several verified edge cases: overlapping
fixed profiles can crash projection, split same-day charges can inflate
recurrence confidence, dismissed patterns can fragment after source-pattern
removal, excluded categories can create irrelevant review work, generated
profiles can block category deletion, seed reruns can overwrite decisions, and
the fixed-commitments table can clip on narrow screens.

## Solution

- Compare overlapping profile ranks with Ruby's spaceship operator.
- Collapse expense evidence by billing date before calculating recurrence and
  occurrence amounts.
- Keep dismissed profile patterns available only for stable grouping.
- Exclude excluded-category suggestions from detection and projection review.
- Destroy dependent expense profiles when deleting an otherwise-unused category.
- Seed classifications and profiles only when they have not already been set.
- Make the fixed-commitments table horizontally scrollable.
- Add regression coverage for each behavioral defect.

## Files

- Cost of Living projection and detection services and tests
- Category association and admin category controller tests
- Development seeds
- Cost of Living view

## Considerations

The review's recommendation to warn whenever mixed coverage is below 100% is
intentionally not adopted. Subsequent product feedback established mixed
remainder as a valid steady state that must be neutrally disclosed rather than
presented as an actionable warning.

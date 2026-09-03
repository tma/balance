# Restore CI for Dependency Pull Requests

## Problem

All open Dependabot pull requests inherit failures from `main`. The model test
expects broker synchronization to create one month-end valuation, but the asset
save callback first creates a second valuation for the current date. The Ruby
security scan also rejects the locked Brakeman version because the binstub
requires the latest release. Older dependency branches additionally contain
lockfile combinations that omit the `ruby-vips` runtime dependency.

## Proposed Solution

1. Make broker synchronization pass its month-end date through the existing
   valuation callback so the callback and explicit upsert target one record.
2. Strengthen the model test to verify the single valuation is month-end.
3. Update Brakeman to the latest compatible release in `Gemfile.lock`.
4. Land the CI repair on `main`, update the remaining Dependabot branches, and
   use the GitHub pull-request API to squash-merge each non-superseded update.

## Files to Modify

- `app/models/asset.rb`
- `test/models/asset_test.rb`
- `Gemfile.lock`
- `doc/plans/restore-ci-for-dependency-prs.md`

## Considerations

- Unchanged broker values must still create or update the month-end valuation,
  so the explicit valuation upsert remains necessary.
- The temporary valuation date must not leak into later saves on a reused model
  instance.
- Dependency pull requests that are fully superseded by a newer grouped update
  should not be merged independently.
- Every pull request merge must use the GitHub PR API with
  `merge_method=squash`.

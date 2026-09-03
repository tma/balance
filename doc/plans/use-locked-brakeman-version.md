# Use the Locked Brakeman Version

## Problem

The Brakeman binstub adds `--ensure-latest` to every invocation. This makes CI
fail whenever RubyGems publishes a newer Brakeman release, even when the locked
version completes the security scan successfully.

## Proposed Solution

Remove `--ensure-latest` from the binstub. Bundler will continue to run the
version recorded in `Gemfile.lock`, while Dependabot remains responsible for
proposing Brakeman upgrades.

## Files to Modify

- `bin/brakeman`
- `doc/plans/use-locked-brakeman-version.md`

## Considerations

- Keep the existing CI command so local and CI scans use the same binstub.
- Brakeman warnings must still fail CI; only the unrelated latest-version check
  is removed.

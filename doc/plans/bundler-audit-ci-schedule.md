# Bundler Audit CI Schedule

## Problem

`bin/bundler-audit` fails pull request CI whenever a new advisory is published against the current lockfile. The signal is useful, but it can block unrelated changes before Dependabot has had a chance to open or merge a dependency update.

## Proposed Change

Keep Ruby security scanning, but split the responsibilities:

- Keep Brakeman in the main `CI` workflow for pull requests and pushes to `main`.
- Move `bundler-audit` to a separate workflow that runs:
  - on pushes to `main`
  - on a weekly schedule
  - manually via `workflow_dispatch`

This keeps advisory detection visible without making unrelated pull requests fail because of newly published dependency advisories.

## Files To Modify

- `.github/workflows/ci.yml`
- `.github/workflows/ruby-security.yml`
- `Gemfile.lock` from the advisory updates

## Validation

Run the same local checks:

```bash
docker exec balance-devcontainer bin/brakeman --no-pager
docker exec balance-devcontainer bin/bundler-audit
docker exec balance-devcontainer bin/rails test
docker exec balance-devcontainer rubocop
```

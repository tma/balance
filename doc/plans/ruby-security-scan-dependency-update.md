# Ruby Security Scan Dependency Update

## Problem

The GitHub Actions `CI` workflow is failing in `scan_ruby` on pushes to `main`.

`bin/brakeman --no-pager` passes with zero warnings. `bin/bundler-audit` fails because the latest advisory database flags vulnerable locked transitive gems:

- `crass 1.0.6` — solution `>= 1.0.7`
- `msgpack 1.8.1` — solution `>= 1.8.2`

## Proposed Fix

Update the lockfile for the affected gems only:

```bash
docker exec balance-devcontainer bundle update crass msgpack
```

Then run the same checks CI runs:

```bash
docker exec balance-devcontainer bin/brakeman --no-pager
docker exec balance-devcontainer bin/bundler-audit
docker exec balance-devcontainer bin/rails test
docker exec balance-devcontainer rubocop
```

## Files Expected To Change

- `Gemfile.lock`
- this plan document

## CI Scan Assessment

Keep `scan_ruby` in CI. Dependabot is useful for opening dependency PRs, but `bundler-audit` catches newly published advisories against the current lockfile immediately. That can be annoying on unrelated changes, but the signal is real and the fix is usually a small lockfile-only update.

The tradeoff is whether to make the job blocking. For this app, keeping it blocking is acceptable if we handle these updates promptly. If the noise becomes too high, a better compromise is to run the security scan on a schedule and on `main`, while keeping pull request CI focused on tests and lint.

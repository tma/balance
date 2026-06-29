# Dependabot Grouped PR Configuration

## Overview
Update Dependabot configuration so each update job opens grouped pull requests instead of one pull request per dependency.

## Problem
Current `.github/dependabot.yml` schedules weekly updates for Bundler and GitHub Actions, but each dependency can open its own PR. This can increase PR noise and maintenance overhead.

## Proposed Solution
Add a `groups` block to each ecosystem entry (`bundler` and `github-actions`) with a wildcard pattern so all version updates are grouped into a single PR per ecosystem.

## Files To Modify
- `.github/dependabot.yml`

## Considerations
- Keep existing schedule and PR limit settings unchanged.
- Use valid Dependabot grouping syntax (`patterns: ["*"]`).
- This change should not affect application runtime behavior.

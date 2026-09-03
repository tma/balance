# Install Libvips in CI

## Problem

The grouped dependency update declares `ruby-vips`, but GitHub-hosted Ubuntu
runners do not include the native libvips library. Rails boot, system tests, and
the importmap audit fail while the production Docker build succeeds because the
Docker image already installs libvips.

## Proposed Solution

Install the Ubuntu `libvips-dev` package in CI jobs that boot the Rails
application.

## Files to Modify

- `.github/workflows/ci.yml`
- `doc/plans/install-libvips-in-ci.md`

## Considerations

- The Brakeman and RuboCop jobs do not load the image-processing runtime and do
  not need the package.
- Use Ubuntu's stable development package name so the runtime library is pulled
  in across runner image updates.

# Add the Ruby Vips Runtime Dependency

## Problem

The grouped dependency update moves `image_processing` to 2.0.3. That release
requires applications using its Vips backend to include `ruby-vips` directly.
Without it, Rails cannot boot, tests cannot start, and production asset
precompilation fails.

## Proposed Solution

Declare `ruby-vips` as an application dependency next to `image_processing` and
refresh the lockfile.

## Files to Modify

- `Gemfile`
- `Gemfile.lock`
- `doc/plans/add-ruby-vips-runtime-dependency.md`

## Considerations

- Keep the version constraint on the supported ruby-vips 2.x series.
- Validate both Rails boot paths and the production Docker build.

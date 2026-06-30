# IBKR Linked Asset Valuations Fix

## Problem

In production, IBKR sync imports positions but no longer applies the imported values to linked assets as asset valuations.

## Current Flow

1. `IbkrSyncService#perform_sync!` fetches IBKR positions.
2. Each position updates a `BrokerPosition` and records a `PositionValuation` for the sync date.
3. For today's sync only, `BrokerSyncService#sync_mapped_assets` finds linked positions for the connection and calls `Asset#sync_from_broker_positions!`.
4. `Asset#sync_from_broker_positions!` totals linked open broker positions, updates the asset value, and creates/updates the current month `AssetValuation`.

## Investigation Plan

- Run baseline `rails test` and `rubocop` inside the devcontainer.
- Review schema/migrations around the IBKR mapping refactor.
- Trace how linked positions are selected and whether production data can be missed by current queries.
- Reproduce with a test that syncs an IBKR-linked asset and asserts both current asset value and asset valuation are updated.
- Fix the sync path so imported IBKR values reliably produce linked asset valuations.

## Likely Areas to Modify

- `app/services/broker_sync_service.rb`
- `app/services/ibkr_sync_service.rb`
- `app/models/asset.rb`
- `test/services/ibkr_sync_service_test.rb` or focused model/service tests

## Considerations

- Keep controllers thin and use existing model/service conventions.
- Preserve historical `PositionValuation` behavior and IBKR FX-rate passthrough.
- Do not write historical `AssetValuation` records from broker sync; past asset valuations are manually confirmed.
- Avoid changing the public linking UI unless the bug is in the mapping model/UI.
- Run focused tests first, then full `rails test` and `rubocop` after the fix.

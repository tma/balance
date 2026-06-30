# Broker Valuation Feature Review

## Problem

After fixing IBKR sync date propagation into linked asset valuations, review the broader broker valuation feature for additional correctness or reliability bugs.

## Scope

Review the full broker valuation flow:

1. Broker sync entry points (`BrokerSyncBackfillService`, `BrokerSyncJob`, admin sync action).
2. Broker-specific sync services (`IbkrSyncService`, `ManualSyncService`).
3. Position lifecycle and valuation creation (`BrokerPosition`, `PositionValuation`).
4. Linked asset application (`BrokerSyncService#sync_mapped_assets`, `Asset#sync_from_broker_positions!`).
5. Admin mapping/apply paths (`Admin::BrokerPositionsController`, `AssetValuationsController#apply_broker_values`).
6. Tests and fixtures around the above.

## Review Focus

- Date correctness for broker-owned position valuations.
- Asset valuations are manually managed for past months; software may only update the current month.
- Behavior when positions are closed, reopened, unmapped, or mapped to multiple assets.
- Multi-currency valuation and exchange-rate date handling.
- Side effects from `Asset` callbacks when broker sync creates valuations.
- Gaps between cached broker value application and live broker sync.
- Missing tests for critical production paths.

## Implementation Plan

- Gather current diffs and read the full files in scope.
- Identify concrete bugs only; avoid speculative changes.
- Add focused failing tests for each bug before/with fixes.
- Do not add any service/task that backfills historical asset valuations.
- Keep fixes small and consistent with existing Rails conventions.
- Run focused tests, then full `rails test` and `rubocop` in the devcontainer.

## Files Likely To Change

- `app/models/asset.rb`
- `app/models/broker_position.rb`
- `app/services/broker_sync_service.rb`
- `app/services/ibkr_sync_service.rb`
- `app/services/manual_sync_service.rb`
- `app/controllers/asset_valuations_controller.rb`
- `test/models/asset_test.rb`
- `test/models/broker_position_test.rb`
- `test/services/*sync*_test.rb`

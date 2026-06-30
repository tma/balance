# IBKR Manual Sync Zero Valuations Debug

## Problem

After deploying the broker sync boundary fix, clicking manual sync for the IBKR broker in production still leaves all linked assets with current-month asset valuations of 0.

## Current Hypotheses

1. Today's IBKR report is parsed as zero positions, so the current sync closes/zeros positions and linked assets are correctly calculated as 0 from bad input.
2. Broker positions have non-zero values but are closed or unmapped, so linked assets see no open broker positions.
3. Broker positions are open, mapped, and non-zero, but `sync_mapped_assets` is not selecting/reloading the right assets.
4. The backfill/manual sync path is doing historical syncs before today's sync and leaving state in a shape that today's sync does not correct.

## Review Plan

- Re-read manual sync entry point and `BrokerSyncBackfillService` ordering.
- Re-read `IbkrSyncService#perform_sync!`, position update/close behavior, and `sync_mapped_assets_if_current`.
- Re-read `Asset#total_broker_value` and `Asset#sync_from_broker_positions!`.
- Add production-safe result details/logging if current sync cannot explain what happened from the UI.
- Add tests for any concrete bug found.

## Findings

Production facts ruled out an empty IBKR report and closed/unmapped positions. The remaining likely failure is the asset application currency conversion step: broker positions can have non-zero values in their own currencies while linked asset sync still fails to convert them into the asset currency.

Today's IBKR sync already records `PositionValuation#value_in_default_currency` using the IBKR-provided FX rate when the IBKR base currency matches the app default. For default-currency linked assets, `Asset#total_broker_value` should prefer that broker valuation before falling back to the external exchange-rate service.

Manual sync should also sync today first, so the button immediately refreshes current linked assets before any historical position backfill runs. The flash message should include today's position count, updated asset count, and closed position count to make production diagnosis visible.

## Constraints

- Historical `AssetValuation` records are manually confirmed and must not be touched.
- Software owns broker `PositionValuation` records.
- Current/today broker sync may update current broker position state and current-month linked asset valuations.
- Use the devcontainer for Rails/Bundler commands.

## Validation

Run focused tests for IBKR sync and broker asset application, then full `rails test` and `rubocop` if code changes are made.

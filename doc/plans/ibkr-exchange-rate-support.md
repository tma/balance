# IBKR Exchange Rate Support for Position Valuations

## Problem

Broker position valuations were showing the same currency exchange rate across multiple days, which was incorrect. Investigation revealed two issues:

1. Exchange rates were coming from a separate API (frankfurter.app), not from IBKR's Flex Query response
2. The `date:` parameter wasn't being passed to `ExchangeRateService.rate()`, so all valuations got the current rate instead of historical rates

## Solution

### 1. Add IBKR Exchange Rate Support

Modified `app/services/ibkr_sync_service.rb` to parse:
- `fxRateToBase` attribute from each `OpenPosition` element
- `currency` attribute from `AccountInformation` section (the IBKR account's base currency)

These values are now passed through position data to `PositionValuation`.

### 2. Update PositionValuation Model

Modified `app/models/position_valuation.rb` to:
- Accept virtual attributes `fx_rate_to_base` and `ibkr_base_currency`
- Use IBKR's rate when IBKR base currency matches app's default currency
- Fall back to `ExchangeRateService` with the valuation's date when currencies don't match

### 3. Make `date:` Mandatory in ExchangeRateService

Updated `app/services/exchange_rate_service.rb` to require the `date:` parameter (no more defaulting to "latest").

Updated all callers to pass dates:
- `app/models/account.rb` - uses `Date.current`
- `app/models/asset.rb` - uses `Date.current`
- `app/models/asset_valuation.rb` - uses valuation's `date`
- `app/models/transaction.rb` - already had `date:`
- `app/models/position_valuation.rb` - already had `date:`

### 4. Refactor Valuation Recording

Modified `IbkrSyncService` to record valuations inline during `perform_sync!` (where position_data with FX rates is available), rather than in the base class `BrokerSyncService` afterward.

Added `records_valuations_inline?` method to allow subclasses to opt out of generic valuation recording.

### 5. Update Tests

- Rewrote `test/services/exchange_rate_service_test.rb` for mandatory `date:` parameter
- Added new tests in `test/services/ibkr_sync_service_test.rb` for FX rate parsing and usage

### 6. Update README

Added a "Broker Connections" section with IBKR subsection explaining:
- How to create a Flex Query with required fields
- How to generate a Flex Web Service token
- How to add the connection in Balance
- Currency conversion behavior

## Files Modified

- `app/services/ibkr_sync_service.rb`
- `app/services/broker_sync_service.rb`
- `app/services/exchange_rate_service.rb`
- `app/models/position_valuation.rb`
- `app/models/account.rb`
- `app/models/asset.rb`
- `app/models/asset_valuation.rb`
- `test/services/exchange_rate_service_test.rb`
- `test/services/ibkr_sync_service_test.rb`
- `README.md`

## IBKR Flex Query Fields Required

**AccountInformation section:**
- `currency` (account base currency)

**OpenPositions section:**
- `symbol`, `longName`/`description`, `position`, `positionValue`/`markValue`, `currency`, `listingExchange`, `fxRateToBase`, `levelOfDetail`

**CashReport section:**
- `currency`, `endingCash`, `fxRateToBase`

## Commits

1. `1b11a4e` - Make ExchangeRateService date parameter mandatory
2. `34763b6` - Add IBKR exchange rate support for position valuations
3. `aaee332` - Document IBKR broker connection setup in README

## Future Considerations

- Backfill historical valuations with corrected exchange rates if needed
- User should update their IBKR Flex Query to include `AccountInformation.Currency` and `OpenPosition.FxRateToBase` fields

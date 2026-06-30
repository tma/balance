# IBKR Conversion Rates Support

## Problem

IBKR Cash Report rows may not include `fxRateToBase`, so cash positions such as USD cash cannot use IBKR-provided rates for default-currency conversion. Flex Query can include a `ConversionRates` section with rows like:

```xml
<ConversionRate reportDate="2026-06-29" fromCurrency="USD" toCurrency="CHF" rate="0.80759" />
```

Balance should use these rates before falling back to the external `ExchangeRateService`.

## Proposed Solution

- Parse all `ConversionRate` rows from the IBKR Flex XML.
- Use direct `fxRateToBase` first when IBKR base currency matches app default.
- Use `ConversionRate` for `currency -> app default currency` when direct `fxRateToBase` is missing or points to a non-default IBKR base currency.
- Fall back to existing behavior:
  - same-currency rate of `1.0`
  - external `ExchangeRateService`
- Apply this to both `OpenPosition` and `CashReportCurrency` rows.

## Files To Modify

- `app/services/ibkr_sync_service.rb`
- `test/services/ibkr_sync_service_test.rb`
- possibly `README.md` to document adding `ConversionRates` to the Flex Query

## Validation

- Focused IBKR sync tests.
- Full `rails test` and `rubocop`.

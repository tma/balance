# Fix: Today's Position Valuations Not Updated During Manual Sync

## Problem

When running the brokersync job manually, position valuations for TODAY are not being updated with current market values.

## Root Cause

In `IbkrSyncService#request_report`, when a `sync_date` is provided (including today), the code passes `FromDate` and `ToDate` parameters to the IBKR Flex API:

```ruby
if sync_date
  date_str = sync_date.strftime("%Y%m%d")
  params[:FromDate] = date_str
  params[:ToDate] = date_str
end
```

The IBKR Flex Web Service interprets date range parameters as requests for **end-of-day historical data**. For today's date, this data either:
1. Doesn't exist yet (if markets are open)
2. Returns yesterday's closing values
3. Returns stale data

## Solution

When syncing for today (`Date.current`), do NOT pass date parameters to the IBKR API. This allows the Flex API to return the **current portfolio snapshot** with live/recent market values.

Date parameters should only be used for historical backfill dates (dates before today).

## Implementation

Modify `IbkrSyncService#request_report` to skip date parameters when `sync_date == Date.current`:

```ruby
def request_report(sync_date: nil)
  ...
  # Only add date parameters for historical dates, not for today
  # IBKR returns current snapshot when no dates specified, but EOD data when dates are specified
  if sync_date && sync_date < Date.current
    date_str = sync_date.strftime("%Y%m%d")
    params[:FromDate] = date_str
    params[:ToDate] = date_str
  end
  ...
end
```

## Files to Modify

- `app/services/ibkr_sync_service.rb` - Update `request_report` method

## Testing

- Existing tests should continue to pass
- Manual verification: Run sync and confirm today's valuations are updated with current values

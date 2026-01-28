# Broker Sync: Always Include Today

## Problem

The `BrokerSyncBackfillService` only syncs dates where position valuations are **missing**. If today already has a valuation record (even if stale from an earlier sync), it's skipped.

This is incorrect behavior because:
- Markets (including crypto) can be open at any time
- Today's values should always be refreshed to get the latest prices
- The job runs at 5pm ET, which should capture end-of-day values

## Current Behavior

In `BrokerSyncBackfillService.sync_missing_dates!`:
1. Calls `missing_dates_for` which only returns dates with missing valuations
2. Special case: if no missing dates AND no open positions, syncs today (to discover new positions)
3. If today already has valuations, it's not included in the sync

## Proposed Solution

Modify `sync_missing_dates!` to always include `Date.current` in the list of dates to sync, ensuring today's values are always refreshed.

### Changes to `app/services/broker_sync_backfill_service.rb`

```ruby
def self.sync_missing_dates!(connection, window_days: WINDOW_DAYS)
  dates = missing_dates_for(connection, window_days: window_days)
  
  # Always include today to get latest values (markets may still be open)
  dates << Date.current unless dates.include?(Date.current)

  return { dates: [], synced: 0 } if dates.empty?

  service = BrokerSyncService.for(connection)

  dates.each_with_index do |date, index|
    pause(BACKFILL_DELAY) if index.positive?
    service.sync!(sync_date: date)
  end

  { dates: dates, synced: dates.count }
end
```

The special case on lines 10-12 can be removed since today will always be included:
```ruby
# REMOVE THIS:
if dates.empty? && connection.broker_positions.open.none?
  dates = [ Date.current ]
end
```

## Files to Modify

1. `app/services/broker_sync_backfill_service.rb` - Add today to sync dates, remove redundant special case

## Testing

1. Update existing tests in `test/services/broker_sync_backfill_service_test.rb` to verify today is always included
2. Verify that the sync service handles updating existing valuations (upsert behavior)

## Verification

After implementation:
```ruby
# Should always include Date.current
BrokerSyncBackfillService.missing_dates_for(connection) # may or may not include today
# But sync_missing_dates! should always sync today regardless
```

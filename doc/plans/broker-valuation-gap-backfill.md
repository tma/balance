# Broker Valuation Gap Backfill (14 Days)

## Overview

Ensure broker sync fills valuation gaps within the last 14 days by inspecting `position_valuations` instead of relying on `last_sync_date`. Both the daily job and the manual "Sync Now" action use the same backfill logic. Requests run sequentially with a 5-second delay between IBKR requests.

## Goals

1. **Strict gap detection**: A date is missing if any open broker position lacks a valuation for that date.
2. **Backfill window**: Only inspect the last 14 days (inclusive).
3. **Unified behavior**: Manual sync and scheduled job use the same logic.
4. **Rate limiting**: 5-second delay between requests.
5. **No `last_sync_date`**: Remove column and logic; rely on valuations + `last_synced_at`.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Gap definition | Any open position missing | Ensures complete daily valuations per connection |
| Window | 14 days | Bounds API volume, covers recent gaps |
| Sync ordering | Oldest → newest | Preserves time order in valuations |
| Rate limiting | 5s delay | Avoid IBKR rate limits |
| Source of truth | `position_valuations` | Reflects actual stored data |

## Implementation Plan

### 1) Create backfill service

**File:** `app/services/broker_sync_backfill_service.rb`

Responsibilities:
- Compute missing dates within the 14-day window for a connection.
- Sync each missing date sequentially.
- Sleep 5 seconds between sync calls.
- If no open positions exist and no missing dates are found, sync today once.

Pseudo-code:
```ruby
class BrokerSyncBackfillService
  WINDOW_DAYS = 14
  BACKFILL_DELAY = 5.seconds

  def self.missing_dates_for(connection, window_days: WINDOW_DAYS)
    end_date = Date.current
    start_date = end_date - (window_days - 1).days
    open_positions = connection.broker_positions.open

    return [] if open_positions.empty?

    position_ids = open_positions.pluck(:id)
    expected_count = position_ids.count

    counts_by_date = PositionValuation
                     .where(broker_position_id: position_ids, date: start_date..end_date)
                     .group(:date)
                     .distinct
                     .count(:broker_position_id)

    (start_date..end_date).select { |date| counts_by_date[date].to_i < expected_count }
  end

  def self.sync_missing_dates!(connection, window_days: WINDOW_DAYS)
    dates = missing_dates_for(connection, window_days: window_days)
    dates = [Date.current] if dates.empty? && connection.broker_positions.open.none?
    return { dates: [], synced: 0 } if dates.empty?

    service = BrokerSyncService.for(connection)
    dates.each_with_index do |date, index|
      sleep(BACKFILL_DELAY) if index.positive?
      service.sync!(sync_date: date)
    end

    { dates: dates, synced: dates.count }
  end
end
```

### 2) Update scheduled job

**File:** `app/jobs/broker_sync_job.rb`

Replace date calculation with the backfill service:
```ruby
result = BrokerSyncBackfillService.sync_missing_dates!(connection)
return if result[:dates].empty?
Rails.logger.info "[BrokerSyncJob] #{connection.name}: synced #{result[:synced]} date(s)"
```

### 3) Update manual sync action

**File:** `app/controllers/admin/broker_connections_controller.rb`

Use the same backfill service to ensure gaps are filled when clicking "Sync Now". Provide a clear flash message showing how many days were synced.

### 4) Drop `last_sync_date`

**Migration:** `remove_last_sync_date_from_broker_connections`

Remove `last_sync_date` column and references.

### 5) Update sync status logic

**File:** `app/models/broker_connection.rb`

Replace `days_behind` with `missing_sync_days`, derived from `BrokerSyncBackfillService.missing_dates_for`.

### 6) Update admin UI

**Files:**
- `app/views/admin/broker_connections/index.html.erb`
- `app/views/admin/broker_connections/show.html.erb`

Display gap status using `missing_sync_days` and remove references to `last_sync_date`.

### 7) Update tests

**New:** `test/services/broker_sync_backfill_service_test.rb`
- Tests for strict missing-date detection.
- Tests for sequential sync behavior.
- Tests for no-open-position case.

**Update:** `test/jobs/broker_sync_job_test.rb`
- Remove `last_sync_date` expectations.
- Stub backfill service to isolate job behavior.

**Update:** `test/models/ibkr_connection_test.rb`
- Adjust status/label tests to use `missing_sync_days`.

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| No open positions | Sync today once |
| Missing valuation for any open position | Date is included in backfill |
| Weekend dates | Included; IBKR may return same data |
| Auth/rate errors | Job logs and exits; next run retries gaps |

## Testing Checklist

- `docker exec balance-devcontainer bin/rails test`
- `docker exec balance-devcontainer rubocop`

## Notes

- Use sequential syncs with `sleep(5)` between requests.
- Avoid using `last_sync_date` in any logic or UI.

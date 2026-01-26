# IBKR Sync with Gap Detection & Backfill

## Overview

Enhance the IBKR broker sync to automatically detect and backfill missed sync days. If a sync fails or the server is down, subsequent runs will identify gaps and fetch historical data for each missing day.

## Goals

1. **Date-specific sync**: Fetch IBKR data for any specific date via `FromDate`/`ToDate` parameters
2. **Gap detection**: Calculate missing dates between `last_sync_date` and today
3. **Sequential backfill**: Sync each missing date, oldest first
4. **Daily valuations**: Store `position_valuation` record per position per synced date
5. **Schedule change**: Run at 5pm ET (1 hour after NYSE close)
6. **Admin visibility**: Show gap status in UI

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Retry strategy | None - gaps filled next day | Simplicity; historical data is always available |
| Gap limit | No limit | Backfill all missing days |
| Calendar handling | Sync all calendar days | Let IBKR return same/empty data for weekends |
| Rate limiting | 5 second delay between requests | Avoid IBKR rate limits during backfill |
| Backfill cap | 90 days maximum | Prevent excessive API calls for very old gaps |
| Schedule | 5pm ET daily | 1 hour after NYSE close ensures EOD data ready |

## Database Changes

### Migration: `add_last_sync_date_to_broker_connections`

| Column | Type | Default | Purpose |
|--------|------|---------|---------|
| `last_sync_date` | date | null | Date of last successfully synced data |

Note: `last_synced_at` (timestamp of sync attempt) and `last_sync_error` already exist.

**Distinction between fields:**
- `last_synced_at` - When we last ran a sync (timestamp, set by `IbkrSyncService`)
- `last_sync_date` - The trading day of the data we last successfully synced (date, set by job)

When backfilling, `last_synced_at` will always be "now" (when the sync ran), but `last_sync_date` tracks which trading day's data we have.

## Code Changes

### 1. `app/services/ibkr_sync_service.rb`

Add `sync_date` parameter to fetch data for a specific date.

**Changes to `perform_sync!`:**
```ruby
def perform_sync!(sync_date: nil)
  # Pass sync_date through to fetch_positions
end
```

**Changes to `fetch_positions`:**
```ruby
def fetch_positions(sync_date: nil)
  reference_code = request_report(sync_date: sync_date)
  # ... rest unchanged
end
```

**Changes to `request_report`:**
```ruby
def request_report(sync_date: nil)
  params = {
    t: @connection.flex_token,
    q: @connection.flex_query_id,
    v: FLEX_VERSION
  }
  
  if sync_date
    date_str = sync_date.strftime("%Y%m%d")
    params[:FromDate] = date_str
    params[:ToDate] = date_str
  end
  
  uri = URI("#{BASE_URL}/SendRequest")
  uri.query = URI.encode_www_form(params)
  # ... rest unchanged
end
```

### 2. `app/services/broker_sync_service.rb`

Pass `sync_date` through sync flow.

**Changes to `sync!`:**
```ruby
def sync!(sync_date: nil)
  date = sync_date || Date.current
  result = perform_sync!(sync_date: date)
  record_position_valuations!(date: date)
  result
end
```

**Changes to `record_position_valuations!`:**
```ruby
def record_position_valuations!(date:)
  @connection.broker_positions.each do |position|
    position.record_valuation!(date: date)
  end
end
```

### 3. `app/jobs/broker_sync_job.rb`

Rewrite to support gap detection and backfill.

**Key changes:**
- Remove `retry_on StandardError` - we rely on gap detection instead of job-level retries
- Add `MAX_BACKFILL_DAYS = 90` cap to prevent excessive API calls
- Add `dates_to_sync_for` logic with fallback to valuation date lookup

```ruby
class BrokerSyncJob < ApplicationJob
  queue_as :default

  BACKFILL_DELAY = 5.seconds
  MAX_BACKFILL_DAYS = 90

  def perform
    Rails.logger.info "[BrokerSyncJob] Starting daily broker sync"

    BrokerConnection.find_each do |connection|
      sync_connection_with_backfill(connection)
    end

    Rails.logger.info "[BrokerSyncJob] Completed daily broker sync"
  end

  private

  def sync_connection_with_backfill(connection)
    dates = dates_to_sync_for(connection)
    
    return if dates.empty?
    
    Rails.logger.info "[BrokerSyncJob] #{connection.name}: #{dates.count} date(s) to sync"
    
    dates.each_with_index do |date, index|
      sleep(BACKFILL_DELAY) if index > 0  # Rate limit between requests
      sync_for_date(connection, date)
    end
  rescue BrokerSyncService::SyncError => e
    Rails.logger.error "[BrokerSyncJob] #{connection.name}: sync failed - #{e.message}"
    # Error recorded on connection; will retry as gap tomorrow
  end

  def dates_to_sync_for(connection)
    last_date = connection.last_sync_date || last_valuation_date_for(connection)
    
    if last_date.nil?
      # Truly first sync ever - just sync today
      [Date.current]
    else
      gap_start = last_date + 1.day
      all_dates = (gap_start..Date.current).to_a
      
      # Cap at MAX_BACKFILL_DAYS to avoid excessive API calls
      if all_dates.size > MAX_BACKFILL_DAYS
        Rails.logger.warn "[BrokerSyncJob] #{connection.name}: gap of #{all_dates.size} days exceeds max, limiting to #{MAX_BACKFILL_DAYS}"
        all_dates.last(MAX_BACKFILL_DAYS)
      else
        all_dates
      end
    end
  end

  # Look up the most recent valuation date from existing position valuations
  # Used when last_sync_date is nil but valuations exist (e.g., migration scenario)
  def last_valuation_date_for(connection)
    connection.broker_positions
              .joins(:position_valuations)
              .maximum('position_valuations.date')
  end

  def sync_for_date(connection, date)
    Rails.logger.info "[BrokerSyncJob] #{connection.name}: syncing #{date}"
    
    service = BrokerSyncService.for(connection)
    result = service.sync!(sync_date: date)
    
    connection.update!(last_sync_date: date)
    
    Rails.logger.info "[BrokerSyncJob] #{connection.name}: synced #{result[:positions].count} positions for #{date}"
  end
end
```

### 4. `config/recurring.yml`

Change schedule from 11:30pm to 5pm ET.

```yaml
daily_broker_sync:
  class: BrokerSyncJob
  queue: default
  schedule: every day at 5pm America/New_York
```

### 5. Admin UI Updates

**`app/views/admin/broker_connections/` (index/show)**

Show sync status with gap information:

| Status | Display |
|--------|---------|
| OK | "Synced Jan 24" (green) |
| Has gaps | "Last synced Jan 20 (3 days behind)" (orange) |
| Never synced | "Never synced" (gray) |
| Error | "Failed: [error message]" (red) |

**Helper method for `BrokerConnection`:**
```ruby
def days_behind
  return nil if last_sync_date.nil?
  (Date.current - last_sync_date).to_i
end

def sync_status_label
  if last_sync_date.nil?
    "Never synced"
  elsif last_sync_error.present?
    "Failed: #{last_sync_error}"
  elsif days_behind > 1
    "#{days_behind} days behind"
  else
    "Synced"
  end
end
```

## File Changes Summary

| File | Action |
|------|--------|
| `db/migrate/YYYYMMDD_add_last_sync_date_to_broker_connections.rb` | Create |
| `app/services/broker_sync_service.rb` | Edit |
| `app/services/ibkr_sync_service.rb` | Edit |
| `app/jobs/broker_sync_job.rb` | Edit |
| `app/models/broker_connection.rb` | Edit (add helpers) |
| `config/recurring.yml` | Edit |
| `app/views/admin/broker_connections/index.html.erb` | Edit |
| `app/views/admin/broker_connections/show.html.erb` | Edit |
| `test/services/ibkr_sync_service_test.rb` | Edit |
| `test/jobs/broker_sync_job_test.rb` | Edit |
| `test/models/broker_connection_test.rb` | Edit |

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| First sync ever (no valuations) | Just sync today |
| `last_sync_date` nil but valuations exist | Look up max valuation date, backfill from there |
| `last_sync_date` is today | Empty date range, nothing to sync (already up to date) |
| Gap > 90 days | Cap at 90 days, log warning, sync most recent 90 days |
| 10-day gap | Syncs all 10 days sequentially (with 5s delays), then today |
| Sync fails on day 3 of gap | Stops at day 3; tomorrow resumes from day 3 |
| Weekend dates | Synced like any other day; IBKR returns Friday's EOD data |
| IBKR rate limit error | Fails, becomes gap, retried tomorrow |
| Auth error (expired token) | Fails, becomes gap, retried tomorrow (needs manual token refresh) |

## Testing Strategy

1. **Unit tests for `IbkrSyncService`**: Verify `FromDate`/`ToDate` params added to request URL
2. **Unit tests for `BrokerSyncJob`**: Verify gap calculation logic
3. **Integration test**: Mock IBKR API, verify multi-day backfill creates correct valuations
4. **Manual test**: Temporarily set `last_sync_date` to 3 days ago, run job, verify backfill

## Future Considerations

- **Market holiday calendar**: Skip holidays to reduce unnecessary API calls
- **Manual backfill UI**: Admin action to trigger sync for specific date range
- **Alerting**: Notify if sync fails for multiple consecutive days

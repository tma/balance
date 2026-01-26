# Manual Sync Button for Broker Connections

## Overview
Add a "Sync Now" button to the broker connection show page that allows users to manually trigger a sync instead of waiting for the daily scheduled job.

## Motivation
- Users may want to sync immediately after making trades
- If there's a sync error, users can retry without waiting 24 hours
- The sync infrastructure already exists (`BrokerSyncService`)

## Implementation

### 1. Routes (`config/routes.rb`)
Add a member route for the sync action:
```ruby
resources :broker_connections, path: "brokers" do
  collection do
    post :test_connection
  end
  member do
    post :sync  # NEW
  end
  # ...
end
```

### 2. Controller (`app/controllers/admin/broker_connections_controller.rb`)
Add `sync` action and update `before_action`:
```ruby
before_action :set_connection, only: %i[show edit update destroy sync]

def sync
  service = BrokerSyncService.for(@connection)
  service.sync!
  redirect_to admin_broker_connection_path(@connection), 
              notice: "Sync completed successfully."
rescue => e
  redirect_to admin_broker_connection_path(@connection), 
              alert: "Sync failed: #{e.message}"
end
```

### 3. View (`app/views/admin/broker_connections/show.html.erb`)
Add Sync button to the left of the Edit button in the header:
```erb
<div class="flex items-center gap-2">
  <%= button_to "Sync Now", 
                sync_admin_broker_connection_path(@connection),
                method: :post,
                form: { data: { turbo_confirm: "This will sync positions from the broker. Continue?" } },
                class: "rounded-lg px-4 py-2 bg-slate-100 hover:bg-slate-200 text-slate-700 font-medium transition" %>
  <%= link_to "Edit", 
              edit_admin_broker_connection_path(@connection), 
              class: "rounded-lg px-4 py-2 bg-slate-100 hover:bg-slate-200 text-slate-700 font-medium transition" %>
</div>
```

## UI Behavior
- Button positioned top-right, left of Edit button
- Confirmation dialog before sync ("This will sync positions from the broker. Continue?")
- Synchronous request (page reloads when complete)
- Success: Flash notice "Sync completed successfully."
- Failure: Flash alert with error message

## Files Modified
| File | Change |
|------|--------|
| `config/routes.rb` | Add `member { post :sync }` |
| `app/controllers/admin/broker_connections_controller.rb` | Add `sync` action, update `before_action` |
| `app/views/admin/broker_connections/show.html.erb` | Add Sync button left of Edit |

## Testing
- Existing tests should pass (no regressions)
- Manual testing: verify button appears, confirmation works, sync executes

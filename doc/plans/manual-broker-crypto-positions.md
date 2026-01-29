# Manual Broker Connection with Crypto Price Sync

## Problem Statement

IBKR crypto positions held at Paxos are **not available via Flex Query**. As documented by IBKR:

> "IB is not party to any transactions in digital assets and does not custody digital assets on your behalf. All digital asset transactions occur on the Paxos Trust Company ("Paxos") exchange. **Any positions in digital assets are custodied solely with Paxos and held in an account in your name outside of IB.**"

This means crypto positions (BTC, ETH, etc.) cannot be automatically synced like other IBKR positions, creating a gap in portfolio tracking.

## Solution

Add a new "Manual" broker connection type that allows:
1. Manual entry of positions (symbol, quantity)
2. Automatic daily price updates from CoinGecko API (free, no API key required)
3. Same mapping workflow as IBKR positions (map to assets for net worth tracking)

Additionally, refactor `BrokerConnection` to be truly generic and extensible for future broker types.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Credentials storage | JSON column | Generic, no schema changes for new brokers |
| `account_id` column | Remove | Not used in API calls, `name` is sufficient |
| Name uniqueness | None enforced | Users can name connections freely |
| Crypto symbol mapping | Lookup table in code | No new columns needed, uses existing `symbol` field |
| Price API | CoinGecko | Free, no API key, verified working |

## CoinGecko API

**Verified working** (Jan 2026):
```bash
curl "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,solana&vs_currencies=usd"
# Response: {"bitcoin":{"usd":83784},"ethereum":{"usd":2787.27},"solana":{"usd":116.57}}
```

**Free tier:**
- No API key required
- 10-30 calls/minute rate limit
- Supports batch requests (multiple coins in one call)
- 60-second data freshness (fine for daily valuations)

## Architecture

### Current Schema
```
broker_connections
├── id
├── name
├── broker_type (enum: ibkr=0)
├── account_id        ← REMOVE (not used in API)
├── flex_token        ← MOVE TO credentials JSON
├── flex_query_id     ← MOVE TO credentials JSON
├── last_synced_at
└── last_sync_error
```

### New Schema
```
broker_connections
├── id
├── name
├── broker_type (enum: ibkr=0, manual=1)
├── credentials       ← NEW: encrypted JSON for broker-specific config
├── last_synced_at
└── last_sync_error
```

### Credentials JSON Examples
```ruby
# IBKR connection
{ "flex_token" => "abc123...", "flex_query_id" => "123456" }

# Manual connection (no credentials needed)
{ }

# Future broker (e.g., Schwab)
{ "api_key" => "xxx", "account_number" => "456" }
```

## Implementation

### 1. Database Migration

```ruby
# db/migrate/YYYYMMDDHHMMSS_refactor_broker_connections_to_json_credentials.rb
class RefactorBrokerConnectionsToJsonCredentials < ActiveRecord::Migration[8.0]
  def up
    # Step 1: Add new credentials column
    add_column :broker_connections, :credentials, :text

    # Step 2: Migrate existing IBKR data to JSON credentials
    BrokerConnection.reset_column_information
    BrokerConnection.find_each do |conn|
      credentials = {}
      credentials["flex_token"] = conn.read_attribute(:flex_token) if conn.read_attribute(:flex_token).present?
      credentials["flex_query_id"] = conn.read_attribute(:flex_query_id) if conn.read_attribute(:flex_query_id).present?
      conn.update_column(:credentials, credentials.to_json) if credentials.any?
    end

    # Step 3: Remove old columns and index
    remove_index :broker_connections, [:broker_type, :account_id]
    remove_column :broker_connections, :account_id
    remove_column :broker_connections, :flex_token
    remove_column :broker_connections, :flex_query_id
  end

  def down
    # Restore old columns
    add_column :broker_connections, :account_id, :string
    add_column :broker_connections, :flex_token, :string
    add_column :broker_connections, :flex_query_id, :string

    # Migrate data back from JSON
    BrokerConnection.reset_column_information
    BrokerConnection.find_each do |conn|
      next unless conn.credentials.present?
      creds = JSON.parse(conn.credentials) rescue {}
      conn.update_columns(
        flex_token: creds["flex_token"],
        flex_query_id: creds["flex_query_id"],
        account_id: "U0000000" # Placeholder since we lost the original
      )
    end

    # Restore index
    add_index :broker_connections, [:broker_type, :account_id], unique: true

    # Remove credentials column
    remove_column :broker_connections, :credentials
  end
end
```

**Important:** The migration copies existing `flex_token` and `flex_query_id` values into the JSON `credentials` column before dropping the old columns. The `down` migration can restore structure but `account_id` values will be lost (acceptable since they weren't used).

### 2. Model Changes

#### `BrokerConnection`

```ruby
# app/models/broker_connection.rb
class BrokerConnection < ApplicationRecord
  has_many :broker_positions, dependent: :destroy

  # Broker types - extendable for future brokers
  enum :broker_type, { ibkr: 0, manual: 1 }

  # Encrypt credentials JSON
  encrypts :credentials

  # Store accessors for convenient access to credentials
  # Each broker type uses different keys
  store :credentials, coder: JSON

  validates :name, presence: true

  # IBKR-specific validations
  validate :validate_ibkr_credentials, if: :ibkr?

  def flex_token
    credentials_hash["flex_token"]
  end

  def flex_token=(value)
    self.credentials = credentials_hash.merge("flex_token" => value).to_json
  end

  def flex_query_id
    credentials_hash["flex_query_id"]
  end

  def flex_query_id=(value)
    self.credentials = credentials_hash.merge("flex_query_id" => value).to_json
  end

  def broker_type_name
    case broker_type
    when "ibkr" then "Interactive Brokers"
    when "manual" then "Manual"
    else broker_type.titleize
    end
  end

  def mapped_positions
    broker_positions.where.not(asset_id: nil)
  end

  def unmapped_positions
    broker_positions.where(asset_id: nil)
  end

  def sync_status
    return :never if last_synced_at.nil?
    return :error if last_sync_error.present?
    return :behind if missing_sync_days.positive?
    :ok
  end

  def missing_sync_days
    return 0 if last_synced_at.nil?
    BrokerSyncBackfillService.missing_dates_for(self).count
  end

  def sync_status_label
    case sync_status
    when :never then "Never synced"
    when :error then "Failed: #{last_sync_error.to_s.truncate(50)}"
    when :behind then "#{missing_sync_days} days behind"
    else "Synced"
    end
  end

  private

  def credentials_hash
    return {} if credentials.blank?
    JSON.parse(credentials) rescue {}
  end

  def validate_ibkr_credentials
    errors.add(:flex_token, "can't be blank") if flex_token.blank?
    errors.add(:flex_query_id, "can't be blank") if flex_query_id.blank?
  end
end
```

#### `BrokerPosition`

```ruby
# app/models/broker_position.rb (additions)

# Map common crypto symbols to CoinGecko IDs
COINGECKO_SYMBOL_MAP = {
  "BTC" => "bitcoin",
  "ETH" => "ethereum",
  "SOL" => "solana",
  "BCH" => "bitcoin-cash",
  "LTC" => "litecoin",
  "ADA" => "cardano",
  "LINK" => "chainlink",
  "DOGE" => "dogecoin",
  "XRP" => "ripple",
  "AVAX" => "avalanche-2",
  "SUI" => "sui"
}.freeze

def coingecko_id
  COINGECKO_SYMBOL_MAP[symbol&.upcase]
end

def crypto_position?
  coingecko_id.present?
end
```

### 3. New Service: `ManualSyncService`

```ruby
# app/services/manual_sync_service.rb
require "net/http"
require "json"

class ManualSyncService < BrokerSyncService
  COINGECKO_API_BASE = "https://api.coingecko.com/api/v3"

  def perform_sync!(sync_date: nil)
    result = { positions: [], updated_count: 0, closed_count: 0, errors: [] }
    valuation_date = sync_date || Date.current

    begin
      # Get crypto positions that can be priced
      crypto_positions = @connection.broker_positions.open.select(&:crypto_position?)
      return result if crypto_positions.empty?

      # Batch fetch prices from CoinGecko
      coingecko_ids = crypto_positions.map(&:coingecko_id).uniq
      prices = fetch_crypto_prices(coingecko_ids)

      # Update each position
      crypto_positions.each do |position|
        price = prices[position.coingecko_id]
        next unless price

        # Calculate value from quantity and price
        quantity = position.last_quantity || 0
        value = (quantity * price).round(2)

        position.update!(
          last_value: value,
          last_synced_at: Time.current
        )

        record_position_valuation!(position, date: valuation_date)
        result[:positions] << position
      end

      result[:updated_count] = result[:positions].count

      # Update mapped assets
      sync_mapped_assets

      @connection.update!(last_synced_at: Time.current, last_sync_error: nil)
    rescue SyncError => e
      @connection.update!(last_sync_error: e.message)
      result[:errors] << e.message
      raise
    rescue StandardError => e
      @connection.update!(last_sync_error: "Unexpected error: #{e.message}")
      result[:errors] << e.message
      raise SyncError, e.message
    end

    result
  end

  def test_connection
    response = fetch_crypto_prices(["bitcoin"])
    if response["bitcoin"].present?
      { success: true, message: "CoinGecko API reachable", btc_price: response["bitcoin"] }
    else
      { success: false, error: "Could not fetch Bitcoin price" }
    end
  rescue => e
    { success: false, error: e.message }
  end

  private

  def records_valuations_inline?
    true
  end

  def fetch_crypto_prices(coingecko_ids)
    return {} if coingecko_ids.empty?

    uri = URI("#{COINGECKO_API_BASE}/simple/price")
    uri.query = URI.encode_www_form(
      ids: coingecko_ids.join(","),
      vs_currencies: "usd"
    )

    response = Net::HTTP.get_response(uri)

    unless response.is_a?(Net::HTTPSuccess)
      raise SyncError, "CoinGecko API error: #{response.code}"
    end

    data = JSON.parse(response.body)

    # Transform to { "bitcoin" => 87234.0, "ethereum" => 3456.0 }
    data.transform_values { |v| v["usd"]&.to_f }
  rescue JSON::ParserError => e
    raise SyncError, "Invalid response from CoinGecko: #{e.message}"
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    raise SyncError, "CoinGecko API timeout: #{e.message}"
  rescue SocketError, Errno::ECONNREFUSED => e
    raise SyncError, "CoinGecko API unreachable: #{e.message}"
  end

  def record_position_valuation!(position, date:)
    return unless position.last_quantity.present?

    valuation = position.position_valuations.find_or_initialize_by(date: date)
    valuation.assign_attributes(
      quantity: position.last_quantity,
      value: position.last_value,
      currency: position.currency || "USD"
    )
    valuation.save!
  end
end
```

### 4. Update Factory

```ruby
# app/services/broker_sync_service.rb
def self.for(connection)
  case connection.broker_type
  when "ibkr"
    IbkrSyncService.new(connection)
  when "manual"
    ManualSyncService.new(connection)
  else
    raise SyncError, "Unknown broker type: #{connection.broker_type}"
  end
end
```

### 5. Update IbkrSyncService

Update to use the new credential accessors (no changes needed if accessors work correctly):

```ruby
# The service already uses @connection.flex_token and @connection.flex_query_id
# These now read from the JSON credentials column via the accessor methods
```

### 6. Controller Updates

#### `Admin::BrokerConnectionsController`

```ruby
# Update connection_params to remove account_id, keep flex_token/flex_query_id
# (they're now virtual attributes that write to credentials JSON)
def connection_params
  params.require(:broker_connection).permit(:name, :broker_type, :flex_token, :flex_query_id)
end

# Update test_connection to handle manual type
def test_connection
  @connection = BrokerConnection.new(connection_params)

  errors = []
  errors << "Name can't be blank" if @connection.name.blank?
  if @connection.ibkr?
    errors << "Flex Token can't be blank" if @connection.flex_token.blank?
    errors << "Flex Query ID can't be blank" if @connection.flex_query_id.blank?
  end

  if errors.any?
    render json: { success: false, error: errors.join(", ") }
    return
  end

  service = BrokerSyncService.for(@connection)
  result = service.test_connection

  render json: result
end
```

#### `Admin::BrokerPositionsController`

Add create/destroy actions for manual connections:

```ruby
def new
  return head :forbidden unless @connection.manual?
  @position = @connection.broker_positions.build(currency: "USD")
end

def create
  return head :forbidden unless @connection.manual?

  @position = @connection.broker_positions.build(position_create_params)

  if @position.save
    redirect_to admin_broker_connection_path(@connection),
      notice: "Position created successfully."
  else
    render :new, status: :unprocessable_entity
  end
end

def destroy
  return head :forbidden unless @connection.manual?

  @position.destroy!
  redirect_to admin_broker_connection_path(@connection),
    notice: "Position deleted.", status: :see_other
end

private

def position_create_params
  params.require(:broker_position).permit(:symbol, :description, :last_quantity, :currency)
end
```

### 7. Route Updates

```ruby
# config/routes.rb
namespace :admin do
  resources :broker_connections do
    member do
      post :sync
      post :test_connection
    end
    resources :broker_positions, path: "positions" do
      collection do
        patch :bulk_update
      end
    end
  end
end
```

### 8. View Updates

#### Connection form - conditional fields

```erb
<%# app/views/admin/broker_connections/_form.html.erb %>
<%= form_with model: [:admin, @connection], data: { controller: "broker-form" } do |form| %>
  <div>
    <%= form.label :broker_type %>
    <%= form.select :broker_type, BrokerConnection.broker_types.keys.map { |k| [k.titleize, k] },
        {}, data: { broker_form_target: "brokerType", action: "change->broker-form#toggleFields" } %>
  </div>

  <div>
    <%= form.label :name %>
    <%= form.text_field :name, placeholder: "My IBKR Account" %>
  </div>

  <%# IBKR-specific fields %>
  <div data-broker-form-target="ibkrFields">
    <div>
      <%= form.label :flex_token %>
      <%= form.text_field :flex_token %>
    </div>
    <div>
      <%= form.label :flex_query_id %>
      <%= form.text_field :flex_query_id %>
    </div>
  </div>

  <%= form.submit %>
<% end %>
```

#### New position form (manual connections)

```erb
<%# app/views/admin/broker_positions/new.html.erb %>
<h1>Add Position</h1>

<%= form_with model: [:admin, @connection, @position] do |form| %>
  <div>
    <%= form.label :symbol, "Symbol" %>
    <%= form.text_field :symbol, placeholder: "BTC", autofocus: true %>
    <p class="text-sm text-gray-500">
      Supported crypto: BTC, ETH, SOL, BCH, LTC, ADA, LINK, DOGE, XRP, AVAX, SUI
    </p>
  </div>

  <div>
    <%= form.label :description %>
    <%= form.text_field :description, placeholder: "Bitcoin" %>
  </div>

  <div>
    <%= form.label :last_quantity, "Quantity" %>
    <%= form.number_field :last_quantity, step: "any", placeholder: "0.15" %>
  </div>

  <div>
    <%= form.label :currency %>
    <%= form.select :currency, ["USD"], {}, disabled: true %>
    <%= form.hidden_field :currency, value: "USD" %>
  </div>

  <%= form.submit "Create Position" %>
<% end %>
```

#### Connection show - add position button for manual

```erb
<%# In app/views/admin/broker_connections/show.html.erb %>
<% if @connection.manual? %>
  <%= link_to "Add Position", new_admin_broker_connection_broker_position_path(@connection), class: "btn" %>
<% end %>
```

## User Workflow

1. **Create Manual Connection**
   - Admin → Broker Connections → New
   - Select "Manual" type
   - Enter name (e.g., "Paxos Crypto")
   - Save

2. **Add Crypto Position**
   - Click "Add Position" on connection page
   - Enter: Symbol "BTC", Quantity "0.15", Description "Bitcoin"
   - Save

3. **Daily Sync (automatic)**
   - `BrokerSyncJob` runs at 5pm ET
   - `ManualSyncService` fetches BTC price from CoinGecko
   - Position value updated: `0.15 × $83,784 = $12,567.60`
   - Valuation recorded for the day

4. **Map to Asset (optional)**
   - Same as IBKR: map position to an Asset for net worth tracking
   - Asset value updates automatically when position syncs

## Files to Create/Modify

### New Files
- `db/migrate/YYYYMMDDHHMMSS_refactor_broker_connections_to_json_credentials.rb`
- `app/services/manual_sync_service.rb`
- `app/views/admin/broker_positions/new.html.erb`
- `app/views/admin/broker_positions/_form.html.erb`
- `test/services/manual_sync_service_test.rb`

### Modified Files
- `app/models/broker_connection.rb` - Remove account_id, add credentials JSON accessors
- `app/models/broker_position.rb` - Add `COINGECKO_SYMBOL_MAP` and helper methods
- `app/services/broker_sync_service.rb` - Update factory method
- `app/services/ibkr_sync_service.rb` - No changes needed (uses same accessors)
- `app/controllers/admin/broker_connections_controller.rb` - Update permitted params
- `app/controllers/admin/broker_positions_controller.rb` - Add new/create/destroy
- `app/views/admin/broker_connections/_form.html.erb` - Conditional fields by type
- `app/views/admin/broker_connections/show.html.erb` - Add position button for manual
- `config/routes.rb` - Add position create/destroy routes
- `test/models/broker_connection_test.rb` - Update for new structure
- `test/services/ibkr_sync_service_test.rb` - Update fixtures

## Testing Strategy

### Unit Tests
- `ManualSyncService` with stubbed CoinGecko responses
- `BrokerPosition#coingecko_id` mapping
- `BrokerConnection` credential accessors
- `BrokerConnection` validations per broker type

### Integration Tests
- Creating manual connection (no IBKR fields required)
- Creating IBKR connection (flex fields required)
- Adding crypto position with valid symbol
- Sync updates position value correctly
- Position valuation recorded
- Migration preserves existing IBKR credentials

## Migration Safety

The migration must be tested to ensure:
1. Existing IBKR connections retain their `flex_token` and `flex_query_id` values
2. Sync continues to work after migration
3. Rollback restores functionality (except `account_id` values)

**Recommended testing approach:**
```bash
# Before migration
rails runner "puts BrokerConnection.pluck(:id, :flex_token, :flex_query_id).inspect"

# Run migration
rails db:migrate

# After migration - verify credentials preserved
rails runner "BrokerConnection.find_each { |c| puts [c.id, c.flex_token, c.flex_query_id].inspect }"

# Test sync still works
rails runner "BrokerConnection.first.tap { |c| BrokerSyncService.for(c).test_connection }"
```

## Acceptance Criteria

- [ ] Migration preserves existing IBKR credentials
- [ ] Can create a "manual" broker connection without IBKR credentials
- [ ] Can create an "ibkr" broker connection with flex credentials
- [ ] Can add positions with symbol (BTC) and quantity to manual connections
- [ ] Crypto symbols auto-map to CoinGecko IDs via lookup table
- [ ] Daily sync job fetches prices and updates position values
- [ ] Position valuations recorded with correct date and value
- [ ] Positions can be mapped to assets for net worth tracking
- [ ] Can delete positions from manual connections
- [ ] All existing IBKR functionality remains unchanged
- [ ] Test connection verifies CoinGecko API is reachable for manual type
- [ ] Test connection verifies IBKR API for ibkr type

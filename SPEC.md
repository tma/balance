# Personal Finance Budgeting App Specification

## Overview
A personal finance budgeting application to track income, expenses, budgets, and assets with a simple, responsive mobile-friendly web UI.  Single-user, no authentication. 

## Tech Stack
- **Framework:** Ruby on Rails 8.x (latest)
- **Database:** SQLite
- **CSS:** Tailwind CSS
- **JavaScript:** Hotwire (Turbo + Stimulus) - Rails default
- **Dependencies:** Minimal - stick to Rails defaults
- **Containerization:** Docker with Docker Compose

## Core Features

### 1. Accounts
- Create/edit/delete financial accounts (checking, savings, credit card, cash)
- Track current balance per account
- Currency per account (USD, EUR, GBP, etc.)
- View account transaction history

### 2. Assets
- Track non-cash assets and liabilities: 
  - **Investments:** Stock portfolios, retirement accounts, crypto
  - **Property:** Real estate, vehicles
  - **Liabilities:** Mortgage, loans
- Fields:  name, asset_type, value, currency, notes
- Manual value updates with history tracking
- Appreciation/depreciation tracking over time
- **Archive feature:**
  - Archive assets that no longer exist or were replaced
  - Archived assets are hidden from main lists but appear in collapsible sections
  - Historical valuations preserved for net worth history
  - Can still backfill historical valuations for archived assets
  - Broker-linked assets cannot be archived (must close positions first)
  - Archived assets excluded from current totals but included in historical charts

### 3. Transactions
- Add income/expense transactions
- Fields: amount, date, description, category, account
- Edit/delete transactions
- **Import from bank statements:** Upload PDF or CSV files for AI-powered extraction

### 4. Transaction Import
- Upload PDF or CSV bank statements
- AI-powered extraction using Ollama LLM (configurable model)
- Automatic category matching based on description
- Duplicate detection via hash of date + amount + description
- Preview extracted transactions before import
- Manual fallback when AI extraction fails
- Max file size: 5MB

### 5. Budgets
- Set recurring budgets per expense category
- Two budget periods:
  - **Monthly:** Track spending per calendar month (e.g., $500/month for groceries)
  - **Yearly:** Track spending per calendar year (e.g., $3000/year for vacation)
- Optional start date to apply budget from a specific month forward
- One budget per category (no duplicates)
- Track spending vs budget with visual progress indicators
- View budget status for any month/year

### 6. Dashboard
Split into two views:

#### Cash Flow View (root path)
- **Year Navigation:**
  - Navigate between calendar years using prev/next arrows
  - URL parameter: `?year=2025`
  - Default to current year
  - Shows all 12 months of the selected year (Jan-Dec)
- **Month Filter:**
  - Clickable month tabs/buttons within the displayed year
  - URL parameter: `?year=2025&month=3` (for March)
  - "Year" option shows full year aggregate
  - Selected month highlighted in the monthly table
  - Donut chart reflects selected period (month or full year)
- **Summary Card** - Compact flow showing: +Income − Expenses = Net (X% saved)
  - Single cohesive card with visual progress bar showing expense/savings ratio
- **Nested Donut Chart:**
  - Inner ring: Income broken down by category (cool tones)
  - Outer ring: Expenses by category + savings slice if positive net (warm tones)
  - Center: Net amount (green if positive, red if negative)
- **Monthly Breakdown Table** - All 12 months of selected year with income/expenses/net/saving rate
  - Current month highlighted, selected month has accent border
  - Links to filtered cash flow view when clicking a month
- **Budget Status** - Two-column layout for monthly and yearly budgets with progress bars
  - Budgets follow the navigation context (selected year/month)
  - Budgets link to filtered transaction list for category and time range

#### Net Worth View
- **Summary Cards:**
  - Cash (all accounts)
  - Total assets
  - Total liabilities
  - Net worth
- **Assets by Group** - Expandable sections showing assets grouped by AssetGroup
  - Each asset shows current value and liability badge if applicable
- **Totals Footer** - Assets - Liabilities = Net

### 7. Broker Integration
- Connect brokerage accounts to auto-sync portfolio positions
- Currently supports Interactive Brokers via Flex Web Service API
- **Setup:**
  - Add broker connection with account ID, name, and API credentials
  - For IBKR: Flex token (encrypted) and Flex Query ID required
  - Create a Flex Query in IBKR Account Management that returns Open Positions
- **Position Mapping:**
  - Each broker position (symbol) can be mapped to an existing Asset
  - Unmapped positions are tracked but don't update any asset
  - Multiple positions can map to the same asset (values summed)
- **Syncing:**
  - Automatic daily sync at 4am via Solid Queue scheduled job
  - "Apply Broker Values" button copies cached position values to assets
  - Position valuations recorded daily for historical tracking
- **UI:**
  - Settings → Brokers for connection management
  - "Broker" badge shown on assets with mapped positions
  - Position history viewable on individual position pages

### 8. Admin
- Manage master data: 
  - **Currencies** - ISO 4217 codes (e.g., USD, EUR, GBP)
  - **Account Types** - name (e.g., checking, savings, credit, cash)
  - **Asset Types** - name, is_liability flag (e. g., property, mortgage)
  - **Categories** - name, category_type (income/expense)
- Seed file populates defaults
- Admin UI to add/edit/delete master data

## Data Models

```ruby
# Master Data (Admin)
Currency
- code:string (ISO 4217, e. g., "USD", unique)
- default:boolean (one currency marked as default for reporting)

AccountType
- name: string (e.g., "checking", "savings")

AssetType
- name:string (e. g., "property", "investment")
- is_liability:boolean (default:  false)

AssetGroup
- name:string (e.g., "Retirement", "Real Estate")
- description:string (optional)

Category
- name:string
- category_type:string (income, expense)

# User Data
Account
- name: string
- account_type_id:references
- balance: decimal
- currency:string (ISO 4217 code, e. g., "USD")

Asset
- name:string
- asset_type_id:references
- asset_group_id:references (optional)
- value:decimal
- currency:string (ISO 4217 code, e.g., "USD")
- notes:text
- archived:boolean (default: false)

AssetValuation
- asset_id: references
- value:decimal
- date:date

Transaction
- account_id:references
- category_id:references
- amount:decimal
- transaction_type:string (income, expense)
- date:date
- description:string
- exchange_rate:decimal (rate at transaction date)
- amount_in_default_currency:decimal (for reporting)
- duplicate_hash:string (SHA256 for import duplicate detection)

Budget
- category_id:references
- amount:decimal
- period:string (monthly, yearly)
- start_date:date (optional)

BrokerConnection
- broker_type:integer (enum: ibkr=0)
- account_id:string (unique per broker_type)
- name:string (display name)
- flex_token:string (encrypted, IBKR only)
- flex_query_id:string (IBKR only)
- last_synced_at:datetime
- last_sync_error:text

BrokerPosition
- broker_connection_id:references
- symbol:string (e.g., "AAPL", "VTI")
- description:string (security description)
- asset_id:references (optional, null if unmapped)
- last_quantity:decimal
- last_value:decimal
- currency:string
- last_synced_at:datetime
- unique index on [broker_connection_id, symbol]

PositionValuation
- broker_position_id:references
- date:date
- quantity:decimal
- value:decimal
- currency:string
- unique index on [broker_position_id, date]
```

## UI Requirements
- Mobile-first responsive design
- Tailwind CSS for styling
- Simple navigation (bottom nav on mobile, sidebar on desktop)
- Minimal, clean aesthetic

## Pages
1. **Cash Flow** (root path) - 12-month income/expense overview, budget status
2. **Net Worth** - Assets, liabilities, and net worth summary
3. **Transactions** - List with filters (account, category, month/date range), add/edit forms
4. **Import Transactions** - Upload bank statements, preview and import extracted transactions
5. **Accounts** - Account list and management
6. **Assets** - Asset/liability list with value history, grouped by AssetGroup
7. **Budgets** - Budget setup and tracking
8. **Admin** - Master data management
   - Currencies (with default currency setting)
   - Account Types
   - Asset Types
   - Asset Groups
   - Categories
   - Broker connections and position mappings

## Deployment

### Dockerfile
- Multi-stage build for smaller image
- Based on official Ruby image
- Install Node.js for asset compilation
- Precompile assets in build stage
- Run with production settings
- SQLite database stored in volume

### Docker Compose
- Single service for the Rails app
- Volume mount for SQLite database persistence
- Volume mount for Rails storage
- Environment variables for Rails configuration
- Expose port 3000

### Devcontainer
- Includes Ollama service for AI-powered transaction import
- Auto-pulls configured model on first start
- Environment variables:
  - `OLLAMA_HOST` - Ollama API endpoint (default: http://ollama:11434)
  - `OLLAMA_MODEL` - LLM model to use (default: mistral)
  - `OLLAMA_TIMEOUT` - Request timeout in seconds (default: 120)

## Implementation Notes
- Use Rails scaffold generators where appropriate
- Turbo Frames for inline editing
- Turbo Streams for real-time updates
- Stimulus for minimal JS interactions
- DB-level balance updates via callbacks or service objects
- Seed file with default currencies, account types, asset types, and categories
- Store currency as ISO 4217 code string (validated against Currency)
- One currency marked as default for all reporting/dashboard views
- All dashboard amounts converted to default currency using exchange rates
- Swiss-style number formatting: apostrophe as thousand separator (e.g., CHF 1'234.56)
- AssetValuation created automatically when Asset value changes
- Asset.value always reflects current value; history in AssetValuation
- ExchangeRateService fetches rates from Frankfurter API (supports historical dates)
- ExchangeRateService returns nil on API failure; records retry via ExchangeRateRetryJob (every 6 hours)
- Transaction exchange rates captured at transaction date for accurate historical reporting
- Transaction import uses Ollama LLM for extraction and categorization
- Import services: OllamaService, PdfTextExtractorService, CsvParserService, TransactionExtractorService, DuplicateDetectionService
- Broker integration uses factory pattern (BrokerSyncService) for multi-broker support
- IBKR uses Flex Web Service API (2-step: SendRequest → GetStatement)
- IbkrSyncService handles API calls, XML parsing, and asset value sync
- Daily broker sync at 11:30pm via Solid Queue (BrokerSyncJob) with 14-day valuation backfill
- Position valuations track historical position values separately from asset valuations

## Agent Guidelines
See `AGENTS.md` for development guidelines, code style, and task checklists for AI agents working on this project.

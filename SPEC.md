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
- **Import from bank statements:** Upload CSV/XLS/XLSX files for AI-powered extraction

### 4. Transaction Import
- Upload CSV/XLS/XLSX bank statements
- AI-powered extraction using Ollama LLM (configurable model)
- Automatic category matching based on description
- Duplicate detection via hash of date + amount + description
- Preview extracted transactions before import
- Manual fallback when AI extraction fails
- Max file size: 5MB

### 5. AI Auto-Categorization
- Automatic category suggestion for new transactions using a 3-phase hybrid approach:
  1. **Pattern Matching** - Instant matching against category patterns (manual and learned) using word-boundary regex
  2. **Embedding Similarity** - Semantic matching using vector embeddings when patterns don't match
  3. **LLM Fallback** - For ambiguous cases, the LLM picks from the top 3 embedding candidates
- **Category Patterns:**
  - Two sources: "Manual" (user-created) and "Learned" (extracted by LLM from transaction history)
  - Managed in Admin → Categories, with inline CRUD for manual patterns
  - Learned patterns extracted hourly via background job (`CategoryPatternExtractionJob`)
  - Pattern learning also triggered after import confirmation (scoped to categories used in the import)
  - Conflicting learned patterns resolved by highest confidence, then highest match count
- **Embeddings:**
  - Categories and transactions get vector embeddings via Ollama (`mxbai-embed-large`)
  - Embeddings computed asynchronously via background jobs (`CategoryEmbeddingJob`, `TransactionEmbeddingJob`)
  - Cosine similarity used for matching; configurable confidence threshold (default: 0.75)
- **UI Integration:**
  - Transaction form shows AI-suggested category with accept/dismiss controls
  - Suggestion fetched via Stimulus controller calling `suggest_category` endpoint
- Reduces LLM calls by ~70-80% compared to pure LLM categorization
- **Cost Classification:**
  - The configured `OLLAMA_MODEL` suggests whether expense streams are essential, discretionary, or excluded; category essentiality is set by the user
  - Candidate streams reuse existing Manual/Learned category patterns instead of adding a second merchant extraction pipeline
  - Recurrence candidates are grouped by category and normalized merchant; cadence is calculated deterministically from transaction dates
  - Amount variability is shown as evidence but does not disqualify a recurring stream
  - The LLM receives only a candidate identifier, merchant, category, and aggregate recurrence evidence
  - Structured JSON responses require valid candidate identifiers and enum values; malformed or incomplete results remain unclassified
  - Model recurrence hints are advisory and never assign cadence
  - Users review category defaults once and grouped merchant/category expense streams, never individual historical transactions
  - Repeated transactions collapse into one suggestion showing count, date range, typical amount, cadence, confidence, and annual impact
  - One-time purchases normally follow their confirmed category default; material possible annual commitments in mixed or unclassified categories are surfaced
  - Learned cost classifications require user confirmation before they affect reports
  - Bulk acceptance is limited to high-confidence recurrence that agrees with a confirmed category default; high-impact profiles require individual review
  - Deterministic recurrence evidence and manual overrides take precedence over LLM suggestions
  - Classification setup, deterministic recurrence, manual profiles, and reporting remain available when Ollama is unavailable

### 6. Budgets
- Set recurring budgets per expense category
- Two budget periods:
  - **Monthly:** Track spending per calendar month (e.g., $500/month for groceries)
  - **Yearly:** Track spending per calendar year (e.g., $3000/year for vacation)
- Optional start date to apply budget from a specific month forward
- One budget per category (no duplicates)
- Track spending vs budget with visual progress indicators
- View budget status for any month/year

### 7. Dashboard
Cash Flow reporting includes:

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

#### Cost of Living View
- Available from the Cash Flow navigation at `/cash-flow?view=cost_of_living`
- Answers how much income is required to cover the user's essential baseline:
  - **Fixed commitments** - confirmed essential recurring expense streams
  - **Essential variable costs** - non-recurring essential spending based on category defaults and merchant-level overrides
  - **Cost of living baseline** - fixed commitments plus essential variable costs, shown monthly and annually
- Uses the most recent 12 completed months for amounts and up to 36 completed months for recurrence evidence
- The amount and recurrence windows end at a shared Data Complete Through month
- Data Complete Through defaults to the latest fully completed month supported by every active account with transaction-frequency tracking; untracked accounts do not constrain it
- Users can override Data Complete Through for a static report view or return to the automatic coverage-based cutoff
- A non-default cutoff is represented by `through=YYYY-MM` in the Cost of Living URL; the automatic coverage default keeps the clean URL
- Changing the cutoff is GET-only and does not mutate expense-profile evidence; imports and explicit Refresh Suggestions runs perform profile analysis
- The report always discloses the effective 12-month window and whether its cutoff is automatic or manual
- Detects incomplete months once from all transactions in the amount window, then applies the exclusions to amount aggregation and monthly displays; recurrence keeps all eligible 36-month transactions
- Never pads months before the user's transaction coverage; fewer than six included months produce a provisional result
- A fixed commitment requires a confirmed essential profile, cadence, and confirmed occurrence amount
- Profiles in excluded categories never contribute to fixed commitments
- Fixed commitments annualize the confirmed occurrence amount by cadence:
  - Monthly x 12
  - Quarterly x 4
  - Semiannual x 2
  - Annual x 1
- Automatic cadence evidence uses these median interval bands:
  - Monthly: 25-35 days, at least 3 occurrences
  - Quarterly: 75-105 days, at least 3 occurrences
  - Semiannual: 150-215 days, at least 3 occurrences
  - Annual: 330-400 days, at least 2 occurrences
- High recurrence confidence requires at least 3 occurrences, interval coefficient of variation no greater than 0.15, and a current stream
- Medium recurrence confidence allows interval coefficient of variation no greater than 0.30; two-occurrence annual streams are always medium
- Lower-confidence candidates receive no automatic cadence; weekly and biweekly detection is outside v1
- Cadence detection uses expense-direction, non-refund, converted transactions; unique dates form consecutive intervals and a stream is current when it is not overdue
- Overdue candidates may be medium confidence but never high confidence
- Recency is overdue after 1.5 times the cadence's upper interval; overdue confirmed commitments stay included with their confirmed values and a review flag
- Amount changes of at least 20%, cadence-band changes, and overdue streams return confirmed profiles for review without silently changing the baseline
- Essential variable annual cost is the signed total across included completed months divided by included months and multiplied by 12
- The median included-month value is supplementary context only; it does not drive the annual headline
- Category defaults distinguish essential, discretionary, mixed, excluded, and unclassified expenses
- Existing expense categories start unclassified and require one-time confirmation; income categories remain unclassified and ineligible
- The report renders once at least one expense category is confirmed and never derives costs from unconfirmed defaults
- Merchant-level expense profiles can override category defaults for mixed categories or exceptions
- Classification precedence is excluded category, longest matching confirmed profile, then confirmed category default
- Each transaction matches at most one profile and fixed-commitment transactions are excluded from variable totals
- Detection, confirmation, and reporting assign transactions to the longest matching pattern, breaking equal-length ties by lowest profile ID
- Overlapping confirmed recurring profiles annualize only the longest winning pattern; shorter profiles are flagged as superseded
- Initial setup reviews expense categories once, then grouped profiles ordered by projected annual impact
- Candidates use existing category patterns plus unmatched transactions grouped by exact description; no second LLM merchant-normalization pass is added
- A suggested stream enters review when it has medium/high automatic cadence, or when an unmatched stream in an unclassified or mixed category is at least 1% of trailing annual expense outflow
- Bulk acceptance requires high recurrence confidence and agreement with a confirmed category default; profiles at least 5% of trailing annual expense outflow require individual review
- Threshold outflow is positive expense-direction default-currency spending after shared amount-window exclusions; refunds do not reduce the denominator
- Confirmation shows the number of profiles and annual amount affected
- Dismissed profiles stay dismissed; inactive profiles do not affect the baseline
- Confirmed profiles remain effective until explicitly changed or made inactive
- Detection refreshes evidence from stored profile patterns even if their source category pattern is removed, and never changes confirmed, dismissed, or inactive status
- Unreviewed annual impact includes annualized signed spending from unclassified or mixed categories plus non-overlapping queued suggestions; recurring suggestions use median occurrence amount by cadence and no-cadence suggestions use trailing signed spend
- Classified-spend percentage uses classified eligible expense outflow divided by total eligible expense outflow; it is baseline coverage, not a completion target
- Unmatched mixed-category spending is an expected neutral remainder shown persistently in the breakdown, not an actionable warning
- The mixed remainder links to the exact unmatched transactions behind it using the same projection window and profile assignments
- Actionable warnings are reserved for unclassified categories and queued suggestions
- The report shows unreviewed annual impact, baseline coverage, lookback period, excluded months, confidence, low-data warnings, and supporting transactions
- Savings and transfers are excluded; refunds reduce variable costs but do not create recurrence events
- Transactions missing default-currency conversion are excluded and disclosed as pending conversion
- "Minimum monthly income required" equals annual essential cost divided by 12 and is described as an expense baseline, not a tax-adjusted gross-income target

##### Existing Database Rollout
- The migration adds nullable `categories.essentiality` and a new empty `expense_profiles` table; it does not rewrite categories, transactions, budgets, or existing cash-flow results
- Existing expense categories remain unclassified so the release never silently decides what is essential
- The first Cost of Living visit shows guided setup; after one category is confirmed it renders the baseline while preserving unclassified-impact disclosure
- The daily detection job builds grouped suggestions from existing history, and users can run the same detection immediately with **Refresh Suggestions**
- Detection and the report tolerate unavailable Ollama and pending currency conversion; manual category/profile setup remains usable
- Re-running migrations, seeds, or detection is idempotent and does not overwrite confirmed, dismissed, or inactive profiles
- Rolling back removes only Cost of Living classifications and profiles; original financial data remains intact

#### Net Worth View
- **Summary Cards:**
  - Cash (all accounts)
  - Total assets
  - Total liabilities
  - Net worth
- **Assets by Group** - Expandable sections showing assets grouped by AssetGroup
  - Each asset shows current value and liability badge if applicable
- **Totals Footer** - Assets - Liabilities = Net

### 8. Broker Integration
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

### 9. Admin
- Manage master data: 
  - **Currencies** - ISO 4217 codes (e.g., USD, EUR, GBP)
  - **Account Types** - name (e.g., checking, savings, credit, cash)
  - **Asset Types** - name, is_liability flag (e. g., property, mortgage)
  - **Categories** - name, category_type (income/expense), cost-of-living essentiality, category patterns (manual/learned)
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
- essentiality:string (essential, discretionary, mixed, excluded, or null while unreviewed; expense categories only)
- embedding:binary (vector embedding for semantic matching)

CategoryPattern
- category_id:references
- pattern:string (e.g., "AMAZON", "WHOLE FOODS")
- source:string (human, machine; displayed as Manual, Learned)
- confidence:decimal (0.0-1.0, for learned patterns)
- match_count:integer (how many transactions matched)
- unique index on [pattern, source, category_id]

ExpenseProfile
- category_id:references
- merchant_pattern:string (word-boundary match against transaction descriptions)
- essentiality:string (essential, discretionary, excluded, or null while suggested)
- cadence:string (monthly, quarterly, semiannual, annual; optional)
- source:string (human, machine; displayed as Manual, Learned)
- status:string (suggested, confirmed, dismissed, inactive)
- recurrence_confidence:string (high, medium, low)
- confirmed_amount:decimal (required for confirmed recurring profiles)
- trailing_annual_amount:decimal
- occurrence_count:integer
- first_seen_on:date
- last_seen_on:date
- median_amount:decimal
- amount_cv:decimal
- interval_cv:decimal
- detected_cadence:string
- detected_at:datetime
- confirmed_at:datetime
- review_flags:text JSON array (amount_change, cadence_change, overdue, superseded)
- unique index on [merchant_pattern, category_id]

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
- embedding:binary (vector embedding for semantic matching)

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
1. **Cash Flow** (root path) - 12-month income/expense overview, projected year, cost of living baseline, budget status
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
  - `OLLAMA_MODEL` - LLM model to use (default: llama3.1:8b)
  - `OLLAMA_EMBEDDING_MODEL` - Embedding model (default: mxbai-embed-large)
  - `OLLAMA_EMBEDDING_CONFIDENCE` - Cosine similarity threshold (default: 0.75)
  - `OLLAMA_TIMEOUT` - Request timeout in seconds (default: 600)

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
- Import services: OllamaService, CsvParserService, CsvMappingAnalyzerService, DeterministicCsvParserService, DuplicateDetectionService
- Categorization services: CategoryMatchingService (3-phase pipeline), CategoryPatternExtractionJob (learns patterns from history), ExpenseProfileDetectionService (existing merchant patterns, deterministic recurrence evidence, and Ollama-assisted suggestions)
- Projection services: CostOfLivingProjectionService (fixed commitments and essential variable baseline)
- Expense profile suggestions validate the exact JSON schema and do not trust model-provided confidence
- `rails cost_of_living:benchmark` runs the exact production suggestion prompt against labeled synthetic candidates using the configured local Ollama model
- ExpenseProfileDetectionJob runs daily after pattern extraction and after completed imports, batches up to 10 candidates per model call, and limits model classification to 50 new or changed candidates per run
- Background jobs: TransactionEmbeddingJob, CategoryEmbeddingJob, CategoryPatternExtractionJob (hourly), ExpenseProfileDetectionJob (daily and after import), CategorizationMaintenanceJob (daily), EmbeddingModelMigrationJob
- Broker integration uses factory pattern (BrokerSyncService) for multi-broker support
- IBKR uses Flex Web Service API (2-step: SendRequest → GetStatement)
- IbkrSyncService handles API calls, XML parsing, and asset value sync
- Daily broker sync at 11:30pm via Solid Queue (BrokerSyncJob) with 14-day valuation backfill
- Position valuations track historical position values separately from asset valuations

## Agent Guidelines
See `AGENTS.md` for development guidelines, code style, and task checklists for AI agents working on this project.

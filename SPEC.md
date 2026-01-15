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

### 3. Transactions
- Add income/expense transactions
- Fields: amount, date, description, category, account
- Edit/delete transactions

### 4. Budgets
- Set recurring budgets per expense category
- Two budget periods:
  - **Monthly:** Track spending per calendar month (e.g., $500/month for groceries)
  - **Yearly:** Track spending per calendar year (e.g., $3000/year for vacation)
- Optional start date to apply budget from a specific month forward
- One budget per category (no duplicates)
- Track spending vs budget with visual progress indicators
- View budget status for any month/year

### 5. Dashboard
Split into two views:

#### Cash Flow View (root path)
- **12-Month Summary Cards:**
  - Total income
  - Total expenses  
  - Net savings
  - Saving rate percentage
- **Monthly Breakdown Table** - Last 12 months with income/expenses/net/saving rate
- **Budget Status** - Two-column layout for monthly and yearly budgets with progress bars
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

### 6. Admin
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

Budget
- category_id:references
- amount:decimal
- period:string (monthly, yearly)
- start_date:date (optional)
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
4. **Accounts** - Account list and management
5. **Assets** - Asset/liability list with value history, grouped by AssetGroup
6. **Budgets** - Budget setup and tracking
7. **Admin** - Master data management
   - Currencies (with default currency setting)
   - Account Types
   - Asset Types
   - Asset Groups
   - Categories

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
- Transaction exchange rates captured at transaction date for accurate historical reporting

## Agent Guidelines
See `AGENTS.md` for development guidelines, code style, and task checklists for AI agents working on this project.

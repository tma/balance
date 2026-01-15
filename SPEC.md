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
- Set monthly budgets per category
- Track spending vs budget
- Visual progress indicators

### 5. Dashboard
- **Net Worth Summary:**
  - Total cash (all accounts)
  - Total assets
  - Total liabilities
  - Net worth (cash + assets - liabilities)
  - Grouped by currency
- **Account Summary Cards** - Each account with balance and currency
- **Asset Summary Cards** - Each asset with current value
- **Current Month Stats:**
  - Total income
  - Total expenses
  - Net change (income - expenses)
- **Budget Status** - Progress bars for each budget category
- **Recent Transactions** - Last 10 transactions

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

AccountType
- name: string (e.g., "checking", "savings")

AssetType
- name:string (e. g., "property", "investment")
- is_liability:boolean (default:  false)

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

Budget
- category_id:references
- amount:decimal
- month: integer
- year:integer
```

## UI Requirements
- Mobile-first responsive design
- Tailwind CSS for styling
- Simple navigation (bottom nav on mobile, sidebar on desktop)
- Minimal, clean aesthetic

## Pages
1. **Dashboard** - Overview with key metrics (root path)
   - Net worth summary (cash + assets - liabilities)
   - Account summary cards in a grid
   - Asset summary cards
   - Monthly income/expense/net stats
   - Budget progress section
   - Recent transactions list
2. **Transactions** - List with filters, add/edit forms
3. **Accounts** - Account list and management
4. **Assets** - Asset/liability list with value history
5. **Budgets** - Budget setup and tracking
6. **Admin** - Master data management
   - Currencies
   - Account Types
   - Asset Types
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
- Display totals grouped by currency (no automatic conversion)
- AssetValuation created automatically when Asset value changes
- Asset. value always reflects current value; history in AssetValuation

# Balance

A personal finance budgeting application for tracking income, expenses, budgets, and assets with a clean, mobile-friendly web interface.

## Features

- **Cash Flow Dashboard** - 12-month income/expense overview with saving rate tracking
- **Net Worth Tracking** - Monitor cash accounts, assets, and liabilities
- **Transactions** - Record and categorize income and expenses across multiple accounts
- **Budget Management** - Set monthly and yearly budgets with visual progress indicators
- **Multi-Currency Support** - Track accounts and assets in different currencies (USD, EUR, GBP, CHF, etc.)
- **Asset Tracking** - Monitor investments, property, and liabilities with value history
- **Mobile-First Design** - Responsive interface optimized for mobile and desktop

## Running with Docker Compose

### Prerequisites

- Docker and Docker Compose installed
- Rails master key (see below)

### Quick Start

1. Clone the repository:
   ```bash
   git clone https://github.com/tma/balance.git
   cd balance
   ```

2. Set your Rails master key as an environment variable:
   ```bash
   export RAILS_MASTER_KEY=your_master_key_here
   ```
   
   If you don't have a master key, you can generate credentials:
   ```bash
   # Generate new credentials (requires Ruby/Rails installed locally)
   EDITOR=nano rails credentials:edit
   # This creates config/master.key - use its contents
   ```

3. Build and start the application:
   ```bash
   docker compose up -d
   ```

4. The application will be available at http://localhost:3000

5. On first run, the database will be seeded with default currencies, categories, and account types.

### Stopping the Application

```bash
docker compose down
```

### Persistent Data

Transaction data, accounts, and assets are stored in the `rails_storage` Docker volume and persist between restarts.

## Tech Stack

- Ruby on Rails 8.x
- SQLite database
- Tailwind CSS
- Hotwire (Turbo + Stimulus)

## License

See [LICENSE](LICENSE) file for details.

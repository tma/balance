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

### Quick Start

1. Create a `docker-compose.yml` file:
   ```yaml
   services:
     web:
       image: ghcr.io/tma/balance:main
       ports:
         - "3000:80"
       environment:
         - RAILS_ENV=production
         - RAILS_MASTER_KEY=${RAILS_MASTER_KEY}
         - RAILS_LOG_TO_STDOUT=1
       volumes:
         - balance_storage:/rails/storage
       restart: unless-stopped
   
   volumes:
     balance_storage:
   ```

2. Set your Rails master key as an environment variable:
   ```bash
   export RAILS_MASTER_KEY=your_master_key_here
   ```
   
   > **Note:** If you don't have a master key, contact the repository maintainer or generate new credentials by cloning the repo and running `EDITOR=nano rails credentials:edit`

3. Start the application:
   ```bash
   docker compose up -d
   ```

4. The application will be available at **http://localhost:3000**

5. On first run, the database will be seeded with default currencies, categories, and account types.

### Stopping the Application

```bash
docker compose down
```

### Persistent Data

All data (transactions, accounts, assets) is stored in the `balance_storage` Docker volume and persists between restarts.

## Tech Stack

- Ruby on Rails 8.x
- SQLite database
- Tailwind CSS
- Hotwire (Turbo + Stimulus)

## License

See [LICENSE](LICENSE) file for details.

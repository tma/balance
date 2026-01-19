# Balance

A personal finance budgeting application for tracking income, expenses, budgets, and assets with a clean, mobile-friendly web interface.

![Dashboard](doc/home.png)

![Net Worth](doc/net-worth.png)

![Cash Flow](doc/cash-flow.png)

## Features

### Net Worth & Assets
- **Net Worth Tracking** - Monitor assets and liabilities with donut charts, monthly/quarterly bar charts, and historical trends
- **Asset Valuations** - Bulk edit asset values across multiple months with copy-forward functionality
- **Asset Groups** - Organize assets into customizable groups with color coding
- **Multi-Currency Support** - Track accounts and assets in different currencies (USD, EUR, GBP, CHF, etc.)

### Cash Flow & Transactions
- **Cash Flow Dashboard** - 12-month income/expense overview with saving rate tracking
- **Transactions** - Record and categorize income and expenses across multiple accounts
- **AI-Powered Import** *(experimental)* - Import transactions from bank statements (CSV/PDF) using local LLM
- **Budget Management** - Set monthly and yearly budgets with visual progress indicators

### General
- **Dashboard Overview** - Quick snapshot of net worth and recent cash flow at a glance
- **Mobile-First Design** - Responsive interface optimized for mobile and desktop

## Running with Docker Compose

### Prerequisites

- Docker and Docker Compose installed
- (Optional) [Ollama](https://ollama.ai) for AI-powered transaction import

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
         - SECRET_KEY_BASE=${SECRET_KEY_BASE}
         - ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=${ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY}
         - ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=${ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY}
         - ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=${ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT}
         - RAILS_LOG_TO_STDOUT=1
         - TZ=Europe/Berlin  # Timezone (e.g., America/New_York, Asia/Tokyo)
         - OLLAMA_HOST=http://host.docker.internal:11434
       volumes:
         - balance_storage:/rails/storage
       extra_hosts:
         - "host.docker.internal:host-gateway"
       restart: unless-stopped
       depends_on:
         - worker

     worker:
       image: ghcr.io/tma/balance:main
       command: bundle exec rails solid_queue:work
       environment:
         - RAILS_ENV=production
         - SECRET_KEY_BASE=${SECRET_KEY_BASE}
         - ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=${ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY}
         - ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=${ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY}
         - ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=${ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT}
         - RAILS_LOG_TO_STDOUT=1
         - TZ=Europe/Berlin
         - OLLAMA_HOST=http://host.docker.internal:11434
       volumes:
         - balance_storage:/rails/storage
       extra_hosts:
         - "host.docker.internal:host-gateway"
       restart: unless-stopped
   
   volumes:
     balance_storage:
   ```

2. Generate secrets and set them as environment variables:
   ```bash
   # Generate Rails secret key
   export SECRET_KEY_BASE=$(openssl rand -hex 64)

   # Generate Active Record encryption keys (required for broker integration)
   export ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$(openssl rand -hex 16)
   export ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$(openssl rand -hex 16)
   export ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$(openssl rand -hex 16)
   ```

   > **Important:** Save these values securely. If you lose the encryption keys, any encrypted data (like broker API tokens) will become unreadable.

3. Start the application:
   ```bash
   docker compose up -d
   ```

4. The application will be available at **http://localhost:3000**

5. On first run, the database will be seeded with default currencies, categories, and account types.

### Background Worker

The `worker` service runs scheduled jobs including:
- **Daily broker sync** (4am) - Fetches latest positions from connected brokers (e.g., Interactive Brokers)

### AI-Powered Transaction Import

To enable AI-powered transaction import from bank statements:

1. Install and run [Ollama](https://ollama.ai) on your host machine
2. Pull the recommended model:
   ```bash
   ollama pull llama3.1:8b
   ```
3. The app will automatically connect to Ollama via `host.docker.internal:11434`

### Stopping the Application

```bash
docker compose down
```

### Persistent Data

All data (transactions, accounts, assets) is stored in the `balance_storage` Docker volume and persists between restarts.

## Development

### Prerequisites

- Docker and Docker Compose

### Setup

1. Clone the repository
2. Start the devcontainer:
   ```bash
   docker compose -f .devcontainer/docker-compose.yml up -d
   ```
3. Start the development server:
   ```bash
   docker exec -d balance-devcontainer bin/dev
   ```
4. Open http://localhost:3000

### Running Tests

```bash
docker exec balance-devcontainer bin/rails test
docker exec balance-devcontainer rubocop
```

## Tech Stack

- Ruby on Rails 8.x
- SQLite database
- Tailwind CSS
- Hotwire (Turbo + Stimulus)
- Solid Queue (background jobs)
- Ollama (local LLM for AI features)

## License

See [LICENSE](LICENSE) file for details.

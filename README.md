# Balance

A personal finance budgeting application for tracking income, expenses, budgets, and assets with a clean, mobile-friendly web interface.

## Features

- **Cash Flow Dashboard** - 12-month income/expense overview with saving rate tracking
- **Net Worth Tracking** - Monitor cash accounts, assets, and liabilities
- **Transactions** - Record and categorize income and expenses across multiple accounts
- **AI-Powered Import** - Import transactions from bank statements (CSV/PDF) using local LLM
- **Budget Management** - Set monthly and yearly budgets with visual progress indicators
- **Multi-Currency Support** - Track accounts and assets in different currencies (USD, EUR, GBP, CHF, etc.)
- **Asset Tracking** - Monitor investments, property, and liabilities with value history
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
         - RAILS_MASTER_KEY=${RAILS_MASTER_KEY}
         - RAILS_LOG_TO_STDOUT=1
         - TZ=Europe/Berlin  # Timezone (e.g., America/New_York, Asia/Tokyo)
         - OLLAMA_HOST=http://host.docker.internal:11434
       volumes:
         - balance_storage:/rails/storage
       extra_hosts:
         - "host.docker.internal:host-gateway"
       restart: unless-stopped
   
   volumes:
     balance_storage:
   ```

2. Set your Rails master key as an environment variable:
   ```bash
   export RAILS_MASTER_KEY=your_master_key_here
   ```
   
   > **Note:** The Rails master key is required to decrypt encrypted credentials. If deploying your own instance, you'll need to generate your own credentials by cloning the repository and running `EDITOR=nano rails credentials:edit`, which creates a `config/master.key` file.

3. Start the application:
   ```bash
   docker compose up -d
   ```

4. The application will be available at **http://localhost:3000**

5. On first run, the database will be seeded with default currencies, categories, and account types.

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

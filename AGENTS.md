# Agent Guidelines for Balance

## Project Overview
Personal finance budgeting app built with Ruby on Rails 8.x, SQLite, and Tailwind CSS. See `SPEC.md` for full specification.

## Development Environment

**IMPORTANT: Always use the devcontainer for running Rails commands.**

The project uses a devcontainer for consistent development. The system Ruby is outdated and will not work.

### Starting the Devcontainer
```bash
# Check if devcontainer is running
docker ps | grep balance-devcontainer

# If not running, start it (from project root)
docker compose -f .devcontainer/docker-compose.yml up -d

# Or use VS Code: Cmd+Shift+P -> "Dev Containers: Reopen in Container"
```

### Running Commands in Devcontainer
```bash
# All Rails commands must be run via docker exec
docker exec balance-devcontainer bin/rails generate model Foo
docker exec balance-devcontainer bin/rails db:migrate
docker exec balance-devcontainer bin/rails test
docker exec balance-devcontainer rubocop

# Start the development server (runs in background)
docker exec -d balance-devcontainer bin/dev

# Interactive shell in container
docker exec -it balance-devcontainer bash
```

### Always Start the Server
When beginning a session, always ensure the dev server is running:
```bash
docker exec -d balance-devcontainer bin/dev
```
The app will be available at http://localhost:3000

### Playwright / Browser Automation
When using Playwright to access the dev server, use `http://host.docker.internal:3000` instead of `http://localhost:3000`. The `localhost` domain is not reachable from the Playwright browser context.

### Never
- Run `rails`, `ruby`, or `bundle` commands directly on the host machine
- Use system Ruby (it's outdated and incompatible)

## Planning

**IMPORTANT: Always create a plan document BEFORE implementing any feature or fix.**

- Create a new file in `doc/plans/` with a descriptive name (e.g., `feature-name.md`)
- Document the problem, proposed solution, files to modify, and any considerations
- Never modify existing `doc/plans/` files - they serve as historical records
- The plan should be detailed enough that implementation becomes straightforward

## Development Principles

### Always
- Create a `doc/plans/` file before starting implementation
- Run `rails test` and `rubocop` before and after changes
- Follow Rails conventions and best practices
- Use RESTful routes and resourceful controllers
- Keep controllers thin, models fat
- Write tests for new functionality
- Update `SPEC.md` when features change

### Never
- Add unnecessary gems or dependencies
- Skip tests or leave them failing
- Deviate from the spec without updating it
- Use raw SQL when ActiveRecord suffices
- Commit code that breaks existing tests
- Push to remote without first running `rubocop` and `rails test` and ensuring they pass

## Tech Stack Rules

### Rails
- Use Rails 8.x conventions
- Use `rails generate` for scaffolds, models, controllers
- Use Active Record callbacks for balance updates
- Use concerns for shared model logic
- Use service objects for complex business logic

### Database
- SQLite only
- Use migrations for all schema changes
- Use `db/seeds.rb` for default master data
- Validate foreign keys at model level

### Frontend
- Tailwind CSS for all styling
- Hotwire (Turbo + Stimulus) for interactivity
- Turbo Frames for inline editing
- Turbo Streams for real-time updates
- No additional JavaScript frameworks

### Testing
- Use Minitest (Rails default)
- Write model tests for validations and callbacks
- Write controller/integration tests for CRUD operations
- Write system tests for critical user flows

## Code Style

### Models
```ruby
# Good:  validations, associations, scopes at top
class Account < ApplicationRecord
  belongs_to :account_type
  
  validates :name, presence: true
  validates :currency, presence: true, inclusion: { in: -> { Currency.pluck(:code) } }
  validates :balance, numericality: true
  
  scope :by_currency, ->(code) { where(currency: code) }
end
```

### Controllers
```ruby
# Good: thin controller, standard REST actions
class AccountsController < ApplicationController
  def index
    @accounts = Account.includes(:account_type).all
  end
  
  def create
    @account = Account.new(account_params)
    if @account.save
      redirect_to @account, notice: "Account created."
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  private
  
  def account_params
    params.require(:account).permit(:name, :account_type_id, :balance, :currency)
  end
end
```

## Common Tasks

### Adding a New Model
```bash
rails generate model ModelName field:type field:type
rails db:migrate
rails test
```

### Adding a New Controller
```bash
rails generate controller ControllerName action action
rails test
```

### Running the App
```bash
bin/dev                    # Development with live reload
rails server               # Production mode locally
docker compose up          # Docker container
```

### Database Tasks
```bash
rails db:migrate           # Run migrations
rails db:schema:dump:cable  # Refresh Solid Cable schema dump
rails db:schema:dump:queue  # Refresh Solid Queue schema dump
rails db:seed              # Load seed data
rails db:reset             # Drop, create, migrate, seed
```

## Validation Checklist
Before completing any task: 
- [ ] All tests pass (`rails test`)
- [ ] No rubocop offenses (`rubocop`)
- [ ] New code has test coverage
- [ ] `SPEC.md` updated if features changed
- [ ] Migrations are reversible
- [ ] No hardcoded values (use seeds/config)

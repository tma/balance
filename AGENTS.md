# Agent Guidelines for Balance

## Project Overview
Personal finance budgeting app built with Ruby on Rails 8.x, SQLite, and Tailwind CSS. See `SPEC.md` for full specification.

## Development Principles

### Always
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

## File Structure
```
app/
├── controllers/
│   ├── admin/           # Admin namespace for master data
│   ├── accounts_controller.rb
│   ├── assets_controller.rb
│   ├── budgets_controller.rb
│   ├── dashboard_controller.rb
│   └── transactions_controller.rb
├── models/
│   ├── account.rb
│   ├── account_type.rb
│   ├── asset.rb
│   ├── asset_type.rb
│   ├── asset_valuation.rb
│   ├── budget.rb
│   ├── category.rb
│   ├── currency.rb
│   └── transaction.rb
└── views/
    ├── admin/
    ├── accounts/
    ├── assets/
    ├── budgets/
    ├── dashboard/
    └── transactions/
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
rails db:seed              # Load seed data
rails db: reset             # Drop, create, migrate, seed
```

## Validation Checklist
Before completing any task: 
- [ ] All tests pass (`rails test`)
- [ ] No rubocop offenses (`rubocop`)
- [ ] New code has test coverage
- [ ] `SPEC.md` updated if features changed
- [ ] Migrations are reversible
- [ ] No hardcoded values (use seeds/config)

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# =============================================================================
# Master Data (required for app to function)
# =============================================================================

# Currencies (ISO 4217)
puts "Creating currencies..."
currencies = [
  { code: "USD", default: true },
  { code: "EUR", default: false },
  { code: "CHF", default: false }
].map do |attrs|
  Currency.find_or_create_by!(code: attrs[:code]) do |currency|
    currency.default = attrs[:default]
  end
end

# Account Types
puts "Creating account types..."
account_types = {}
%w[checking savings credit cash investment].each do |name|
  account_types[name] = AccountType.find_or_create_by!(name: name)
end

# Asset Types
puts "Creating asset types..."
asset_types = {}
[
  { name: "Property", is_liability: false },
  { name: "Vehicle", is_liability: false },
  { name: "Investment", is_liability: false },
  { name: "Retirement", is_liability: false },
  { name: "Crypto", is_liability: false },
  { name: "Other Asset", is_liability: false },
  { name: "Mortgage", is_liability: true },
  { name: "Auto Loan", is_liability: true },
  { name: "Student Loan", is_liability: true },
  { name: "Credit Card Debt", is_liability: true },
  { name: "Personal Loan", is_liability: true },
  { name: "Other Liability", is_liability: true }
].each do |attrs|
  asset_types[attrs[:name]] = AssetType.find_or_create_by!(name: attrs[:name]) do |at|
    at.is_liability = attrs[:is_liability]
  end
end

# Categories - Income
puts "Creating income categories..."
income_categories = {}
[ "salary", "bonus", "freelance", "investment", "dividends", "rental", "refund", "other income" ].each do |name|
  income_categories[name] = Category.find_or_create_by!(name: name, category_type: "income")
end

# Categories - Expense
puts "Creating expense categories..."
expense_categories = {}
[ "rent", "mortgage", "utilities", "groceries", "dining", "transportation", "gas", "insurance", "healthcare",
  "entertainment", "subscriptions", "clothing", "education", "personal", "travel", "gifts", "charity", "taxes",
  "fees", "maintenance", "savings", "other expense" ].each do |name|
  expense_categories[name] = Category.find_or_create_by!(name: name, category_type: "expense")
end

# Asset Groups
puts "Creating asset groups..."
asset_groups = {}
[
  { name: "Real Estate", description: "Properties and related mortgages" },
  { name: "Investments", description: "Stocks, bonds, and retirement accounts" },
  { name: "Vehicles", description: "Cars, motorcycles, and related loans" },
  { name: "Other Assets", description: "Miscellaneous assets and liabilities" }
].each do |attrs|
  asset_groups[attrs[:name]] = AssetGroup.find_or_create_by!(name: attrs[:name]) do |group|
    group.description = attrs[:description]
  end
end

puts "Master data loaded!"

# =============================================================================
# Development Sample Data (only in development)
# =============================================================================

if Rails.env.development?
  puts "\nCreating development sample data..."

  # ---------------------------------------------------------------------------
  # Accounts (one of each type, multiple currencies)
  # ---------------------------------------------------------------------------
  puts "Creating accounts..."

  accounts = {}

  # Checking accounts
  accounts[:main_checking] = Account.find_or_create_by!(name: "Main Checking") do |a|
    a.account_type = account_types["checking"]
    a.balance = 0  # Will be calculated from transactions
    a.currency = "USD"
  end

  accounts[:euro_checking] = Account.find_or_create_by!(name: "Euro Account") do |a|
    a.account_type = account_types["checking"]
    a.balance = 0
    a.currency = "EUR"
  end

  # Savings accounts
  accounts[:emergency_fund] = Account.find_or_create_by!(name: "Emergency Fund") do |a|
    a.account_type = account_types["savings"]
    a.balance = 0
    a.currency = "USD"
  end

  accounts[:vacation_savings] = Account.find_or_create_by!(name: "Vacation Savings") do |a|
    a.account_type = account_types["savings"]
    a.balance = 0
    a.currency = "USD"
  end

  accounts[:swiss_savings] = Account.find_or_create_by!(name: "Swiss Savings") do |a|
    a.account_type = account_types["savings"]
    a.balance = 0
    a.currency = "CHF"
  end

  # Credit cards
  accounts[:visa] = Account.find_or_create_by!(name: "Visa Credit Card") do |a|
    a.account_type = account_types["credit"]
    a.balance = 0  # Negative balance = debt
    a.currency = "USD"
  end

  accounts[:amex] = Account.find_or_create_by!(name: "Amex Gold") do |a|
    a.account_type = account_types["credit"]
    a.balance = 0
    a.currency = "USD"
  end

  # Cash
  accounts[:wallet] = Account.find_or_create_by!(name: "Wallet Cash") do |a|
    a.account_type = account_types["cash"]
    a.balance = 0
    a.currency = "USD"
  end

  accounts[:euro_cash] = Account.find_or_create_by!(name: "Euro Cash") do |a|
    a.account_type = account_types["cash"]
    a.balance = 0
    a.currency = "EUR"
  end

  # Investment accounts
  accounts[:brokerage] = Account.find_or_create_by!(name: "Brokerage Account") do |a|
    a.account_type = account_types["investment"]
    a.balance = 0
    a.currency = "USD"
  end

  accounts[:roth_ira] = Account.find_or_create_by!(name: "Roth IRA") do |a|
    a.account_type = account_types["investment"]
    a.balance = 0
    a.currency = "USD"
  end

  # ---------------------------------------------------------------------------
  # Assets and Liabilities (one of each type)
  # ---------------------------------------------------------------------------
  puts "Creating assets and liabilities..."

  # Helper to create or update assets
  def seed_asset(name:, asset_type:, asset_group:, value:, currency:, notes:)
    asset = Asset.find_or_initialize_by(name: name)
    asset.asset_type = asset_type
    asset.asset_group = asset_group
    asset.value = value
    asset.currency = currency if asset.new_record? # Can't change currency after creation
    asset.notes = notes
    asset.save!
    asset
  end

  # Real Estate group
  seed_asset(
    name: "Primary Residence",
    asset_type: asset_types["Property"],
    asset_group: asset_groups["Real Estate"],
    value: 450000,
    currency: "USD",
    notes: "3BR/2BA house purchased in 2020"
  )

  seed_asset(
    name: "Home Mortgage",
    asset_type: asset_types["Mortgage"],
    asset_group: asset_groups["Real Estate"],
    value: 320000,
    currency: "USD",
    notes: "30-year fixed at 3.5%, started 2020"
  )

  seed_asset(
    name: "Vacation Condo",
    asset_type: asset_types["Property"],
    asset_group: asset_groups["Real Estate"],
    value: 180000,
    currency: "EUR",
    notes: "Studio apartment in Barcelona"
  )

  # Investments group
  seed_asset(
    name: "401(k)",
    asset_type: asset_types["Retirement"],
    asset_group: asset_groups["Investments"],
    value: 125000,
    currency: "USD",
    notes: "Employer-sponsored retirement account"
  )

  seed_asset(
    name: "Stock Portfolio",
    asset_type: asset_types["Investment"],
    asset_group: asset_groups["Investments"],
    value: 45000,
    currency: "USD",
    notes: "Individual stocks and ETFs"
  )

  seed_asset(
    name: "Bitcoin Holdings",
    asset_type: asset_types["Crypto"],
    asset_group: asset_groups["Investments"],
    value: 12500,
    currency: "USD",
    notes: "0.15 BTC"
  )

  seed_asset(
    name: "Swiss Investment Fund",
    asset_type: asset_types["Investment"],
    asset_group: asset_groups["Investments"],
    value: 25000,
    currency: "CHF",
    notes: "UBS managed fund"
  )

  seed_asset(
    name: "Student Loans",
    asset_type: asset_types["Student Loan"],
    asset_group: asset_groups["Investments"],
    value: 28000,
    currency: "USD",
    notes: "Federal student loans, 4.5% interest"
  )

  # Vehicles group
  seed_asset(
    name: "Toyota Camry",
    asset_type: asset_types["Vehicle"],
    asset_group: asset_groups["Vehicles"],
    value: 22000,
    currency: "USD",
    notes: "2022 model, purchased used"
  )

  seed_asset(
    name: "Car Loan",
    asset_type: asset_types["Auto Loan"],
    asset_group: asset_groups["Vehicles"],
    value: 15000,
    currency: "USD",
    notes: "5-year loan at 4.9%"
  )

  # Other Assets group
  seed_asset(
    name: "Vintage Watch Collection",
    asset_type: asset_types["Other Asset"],
    asset_group: asset_groups["Other Assets"],
    value: 8500,
    currency: "USD",
    notes: "Rolex Submariner and Omega Speedmaster"
  )

  seed_asset(
    name: "Personal Loan from Family",
    asset_type: asset_types["Personal Loan"],
    asset_group: asset_groups["Other Assets"],
    value: 5000,
    currency: "USD",
    notes: "Interest-free loan from parents"
  )

  # ---------------------------------------------------------------------------
  # Transactions (12 months of varied income and expenses)
  # ---------------------------------------------------------------------------
  puts "Creating transactions..."

  # Helper to create transactions without duplicates
  def create_transaction(attrs)
    existing = Transaction.find_by(
      account: attrs[:account],
      date: attrs[:date],
      description: attrs[:description]
    )
    return existing if existing

    Transaction.create!(attrs)
  end

  today = Date.current

  # Seasonal variations for utilities (higher in winter/summer)
  def seasonal_electric_adjustment(month)
    case month
    when 12, 1, 2 then 1.4  # Winter heating
    when 6, 7, 8 then 1.3   # Summer AC
    else 1.0
    end
  end

  # Grocery stores variety
  grocery_stores = [ "Whole Foods", "Trader Joe's", "Costco", "Safeway", "Target" ]

  # Gas stations variety
  gas_stations = [ "Shell", "Chevron", "Mobil", "BP", "Arco" ]

  # Restaurant variety
  restaurants = [
    "Italian bistro", "Thai restaurant", "Sushi place", "Mexican cantina",
    "Steakhouse", "French cafe", "Indian restaurant", "Chinese takeout",
    "Burger joint", "Pizza place", "Mediterranean grill", "Vietnamese pho"
  ]

  # Entertainment variety
  entertainment_options = [
    [ "Movie tickets", 35, 55 ],
    [ "Concert tickets", 80, 200 ],
    [ "Theater show", 60, 150 ],
    [ "Sporting event", 50, 180 ],
    [ "Museum admission", 20, 40 ],
    [ "Bowling night", 30, 60 ],
    [ "Mini golf", 25, 45 ],
    [ "Escape room", 35, 50 ]
  ]

  # Clothing items
  clothing_items = [
    [ "Running shoes", 120, 200 ],
    [ "Winter jacket", 150, 300 ],
    [ "Dress shirt", 50, 100 ],
    [ "Jeans", 60, 120 ],
    [ "Sneakers", 80, 150 ],
    [ "Workout clothes", 40, 80 ],
    [ "Formal wear", 200, 400 ],
    [ "Casual shoes", 70, 130 ]
  ]

  # Generate 12 months of transactions
  12.times do |months_ago|
    month_start = (today - months_ago.months).beginning_of_month
    month_num = month_start.month

    # ===== INCOME =====

    # Salary - twice monthly (1st and 15th)
    create_transaction(
      account: accounts[:main_checking],
      category: income_categories["salary"],
      amount: 4250.00,
      transaction_type: "income",
      date: month_start,
      description: "Paycheck - 1st"
    )

    create_transaction(
      account: accounts[:main_checking],
      category: income_categories["salary"],
      amount: 4250.00,
      transaction_type: "income",
      date: month_start + 14.days,
      description: "Paycheck - 15th"
    )

    # Euro rental income - monthly
    create_transaction(
      account: accounts[:euro_checking],
      category: income_categories["rental"],
      amount: 950.00,
      transaction_type: "income",
      date: month_start + 1.day,
      description: "Barcelona condo rental income"
    )

    # Quarterly dividends (March, June, Sept, Dec)
    if [ 3, 6, 9, 12 ].include?(month_num)
      create_transaction(
        account: accounts[:brokerage],
        category: income_categories["dividends"],
        amount: (100 + rand * 50).round(2),
        transaction_type: "income",
        date: month_start + 5.days,
        description: "Quarterly dividend - VTI"
      )
    end

    # Occasional freelance income (random months)
    if rand < 0.4
      create_transaction(
        account: accounts[:main_checking],
        category: income_categories["freelance"],
        amount: (500 + rand * 1000).round(2),
        transaction_type: "income",
        date: month_start + (10 + rand(10)).days,
        description: [ "Website project", "Consulting gig", "Design work", "Tech support" ].sample
      )
    end

    # Swiss investment interest - quarterly
    if [ 3, 6, 9, 12 ].include?(month_num)
      create_transaction(
        account: accounts[:swiss_savings],
        category: income_categories["investment"],
        amount: (300 + rand * 100).round(2),
        transaction_type: "income",
        date: month_start + 15.days,
        description: "Investment fund interest"
      )
    end

    # Annual bonus in December
    if month_num == 12
      create_transaction(
        account: accounts[:main_checking],
        category: income_categories["bonus"],
        amount: 5000.00,
        transaction_type: "income",
        date: month_start + 20.days,
        description: "Year-end performance bonus"
      )
    end

    # Occasional refunds
    if rand < 0.2
      create_transaction(
        account: accounts[:visa],
        category: income_categories["refund"],
        amount: (20 + rand * 100).round(2),
        transaction_type: "income",
        date: month_start + (5 + rand(15)).days,
        description: [ "Amazon return", "Store credit", "Overcharge refund" ].sample
      )
    end

    # ===== FIXED EXPENSES =====

    # Mortgage - 1st of month
    create_transaction(
      account: accounts[:main_checking],
      category: expense_categories["mortgage"],
      amount: 1850.00,
      transaction_type: "expense",
      date: month_start + 1.day,
      description: "Monthly mortgage payment"
    )

    # Utilities - electric (seasonal variation)
    electric_base = 150
    electric_amount = (electric_base * seasonal_electric_adjustment(month_num)).round(2)
    create_transaction(
      account: accounts[:main_checking],
      category: expense_categories["utilities"],
      amount: electric_amount,
      transaction_type: "expense",
      date: month_start + 3.days,
      description: "Electric bill"
    )

    # Utilities - water
    create_transaction(
      account: accounts[:main_checking],
      category: expense_categories["utilities"],
      amount: (55 + rand * 20).round(2),
      transaction_type: "expense",
      date: month_start + 4.days,
      description: "Water bill"
    )

    # Utilities - gas (higher in winter)
    gas_amount = month_num.in?([ 11, 12, 1, 2, 3 ]) ? (80 + rand * 40).round(2) : (25 + rand * 15).round(2)
    create_transaction(
      account: accounts[:main_checking],
      category: expense_categories["utilities"],
      amount: gas_amount,
      transaction_type: "expense",
      date: month_start + 5.days,
      description: "Natural gas bill"
    )

    # Insurance - home
    create_transaction(
      account: accounts[:main_checking],
      category: expense_categories["insurance"],
      amount: 125.00,
      transaction_type: "expense",
      date: month_start + 5.days,
      description: "Home insurance"
    )

    # Insurance - auto (every 6 months: Jan, July)
    if [ 1, 7 ].include?(month_num)
      create_transaction(
        account: accounts[:main_checking],
        category: expense_categories["insurance"],
        amount: 650.00,
        transaction_type: "expense",
        date: month_start + 10.days,
        description: "Auto insurance - 6 month premium"
      )
    end

    # Health insurance
    create_transaction(
      account: accounts[:main_checking],
      category: expense_categories["healthcare"],
      amount: 250.00,
      transaction_type: "expense",
      date: month_start + 10.days,
      description: "Health insurance premium"
    )

    # Subscriptions - recurring monthly
    create_transaction(
      account: accounts[:visa],
      category: expense_categories["subscriptions"],
      amount: 15.99,
      transaction_type: "expense",
      date: month_start + 1.day,
      description: "Netflix"
    )

    create_transaction(
      account: accounts[:visa],
      category: expense_categories["subscriptions"],
      amount: 10.99,
      transaction_type: "expense",
      date: month_start + 1.day,
      description: "Spotify"
    )

    create_transaction(
      account: accounts[:visa],
      category: expense_categories["subscriptions"],
      amount: 14.99,
      transaction_type: "expense",
      date: month_start + 3.days,
      description: "iCloud Storage"
    )

    create_transaction(
      account: accounts[:amex],
      category: expense_categories["subscriptions"],
      amount: 12.99,
      transaction_type: "expense",
      date: month_start + 8.days,
      description: "New York Times"
    )

    # Euro expenses - condo fees
    create_transaction(
      account: accounts[:euro_checking],
      category: expense_categories["fees"],
      amount: 45.00,
      transaction_type: "expense",
      date: month_start + 5.days,
      description: "Condo HOA fees"
    )

    # ===== VARIABLE EXPENSES =====

    # Groceries - weekly (4 times per month)
    4.times do |week|
      store = grocery_stores.sample
      base_amount = store == "Costco" ? 200 : 130
      create_transaction(
        account: accounts[:visa],
        category: expense_categories["groceries"],
        amount: (base_amount + rand * 50).round(2),
        transaction_type: "expense",
        date: month_start + (week * 7).days,
        description: store
      )
    end

    # Dining out - 4-6 times per month
    (4 + rand(3)).times do |i|
      restaurant = restaurants.sample
      card = [ accounts[:visa], accounts[:amex] ].sample
      create_transaction(
        account: card,
        category: expense_categories["dining"],
        amount: (25 + rand * 100).round(2),
        transaction_type: "expense",
        date: month_start + (3 + i * 4 + rand(3)).days,
        description: "Dinner at #{restaurant}"
      )
    end

    # Gas - twice per month
    2.times do |i|
      create_transaction(
        account: accounts[:visa],
        category: expense_categories["gas"],
        amount: (40 + rand * 25).round(2),
        transaction_type: "expense",
        date: month_start + (2 + i * 14).days,
        description: gas_stations.sample
      )
    end

    # Entertainment - 1-3 times per month
    (1 + rand(3)).times do |i|
      ent = entertainment_options.sample
      create_transaction(
        account: [ accounts[:visa], accounts[:amex], accounts[:wallet] ].sample,
        category: expense_categories["entertainment"],
        amount: (ent[1] + rand * (ent[2] - ent[1])).round(2),
        transaction_type: "expense",
        date: month_start + (7 + i * 7 + rand(5)).days,
        description: ent[0]
      )
    end

    # Personal care - monthly haircut etc
    create_transaction(
      account: accounts[:visa],
      category: expense_categories["personal"],
      amount: (45 + rand * 30).round(2),
      transaction_type: "expense",
      date: month_start + (10 + rand(5)).days,
      description: [ "Haircut", "Haircut and grooming", "Salon visit" ].sample
    )

    # Healthcare - occasional pharmacy, doctor visits
    if rand < 0.6
      create_transaction(
        account: accounts[:visa],
        category: expense_categories["healthcare"],
        amount: (20 + rand * 50).round(2),
        transaction_type: "expense",
        date: month_start + (12 + rand(10)).days,
        description: [ "Pharmacy - prescriptions", "CVS", "Walgreens" ].sample
      )
    end

    # Doctor visit - occasional
    if rand < 0.15
      create_transaction(
        account: accounts[:main_checking],
        category: expense_categories["healthcare"],
        amount: (100 + rand * 150).round(2),
        transaction_type: "expense",
        date: month_start + (5 + rand(15)).days,
        description: [ "Doctor visit copay", "Specialist appointment", "Lab work" ].sample
      )
    end

    # Clothing - occasional (more in spring/fall)
    clothing_chance = month_num.in?([ 3, 4, 9, 10 ]) ? 0.5 : 0.25
    if rand < clothing_chance
      item = clothing_items.sample
      create_transaction(
        account: accounts[:amex],
        category: expense_categories["clothing"],
        amount: (item[1] + rand * (item[2] - item[1])).round(2),
        transaction_type: "expense",
        date: month_start + (10 + rand(15)).days,
        description: item[0]
      )
    end

    # Transportation - car maintenance, repairs
    if rand < 0.3
      create_transaction(
        account: accounts[:main_checking],
        category: expense_categories["transportation"],
        amount: (50 + rand * 150).round(2),
        transaction_type: "expense",
        date: month_start + (5 + rand(20)).days,
        description: [ "Oil change", "Car wash", "Tire rotation", "Car detailing" ].sample
      )
    end

    # Home maintenance - occasional
    if rand < 0.25
      create_transaction(
        account: accounts[:main_checking],
        category: expense_categories["maintenance"],
        amount: (75 + rand * 300).round(2),
        transaction_type: "expense",
        date: month_start + (10 + rand(15)).days,
        description: [ "Lawn service", "Plumber", "Electrician", "HVAC maintenance", "Appliance repair" ].sample
      )
    end

    # Barcelona condo maintenance - occasional
    if rand < 0.3
      create_transaction(
        account: accounts[:euro_checking],
        category: expense_categories["maintenance"],
        amount: (50 + rand * 150).round(2),
        transaction_type: "expense",
        date: month_start + (8 + rand(10)).days,
        description: "Condo maintenance"
      )
    end

    # Fees - occasional bank fees, etc
    if rand < 0.2
      create_transaction(
        account: accounts[:main_checking],
        category: expense_categories["fees"],
        amount: (15 + rand * 35).round(2),
        transaction_type: "expense",
        date: month_start + (10 + rand(15)).days,
        description: [ "Bank wire fee", "ATM fee", "Account fee" ].sample
      )
    end

    # ===== SEASONAL/OCCASIONAL EXPENSES =====

    # Travel - more in summer and December
    travel_chance = month_num.in?([ 6, 7, 8, 12 ]) ? 0.7 : 0.2
    if rand < travel_chance
      # Flight
      create_transaction(
        account: accounts[:amex],
        category: expense_categories["travel"],
        amount: (250 + rand * 400).round(2),
        transaction_type: "expense",
        date: month_start + (5 + rand(10)).days,
        description: [ "Flight tickets", "Airline booking", "Round-trip airfare" ].sample
      )
      # Hotel
      create_transaction(
        account: accounts[:amex],
        category: expense_categories["travel"],
        amount: (150 + rand * 350).round(2),
        transaction_type: "expense",
        date: month_start + (7 + rand(10)).days,
        description: [ "Hotel booking", "Airbnb stay", "Resort reservation" ].sample
      )
    end

    # Gifts - more in December and around holidays
    gift_chance = month_num == 12 ? 0.9 : (month_num.in?([ 2, 5, 11 ]) ? 0.5 : 0.2)
    if rand < gift_chance
      amount = month_num == 12 ? (200 + rand * 300) : (40 + rand * 100)
      create_transaction(
        account: [ accounts[:visa], accounts[:amex] ].sample,
        category: expense_categories["gifts"],
        amount: amount.round(2),
        transaction_type: "expense",
        date: month_start + (10 + rand(15)).days,
        description: month_num == 12 ? "Holiday gifts" : [ "Birthday gift", "Gift for friend", "Anniversary gift" ].sample
      )
    end

    # Charity - more at year end
    charity_chance = month_num == 12 ? 0.8 : 0.15
    if rand < charity_chance
      amount = month_num == 12 ? (200 + rand * 300) : (25 + rand * 75)
      create_transaction(
        account: accounts[:main_checking],
        category: expense_categories["charity"],
        amount: amount.round(2),
        transaction_type: "expense",
        date: month_start + (15 + rand(10)).days,
        description: [ "Charitable donation", "Red Cross", "Local food bank", "NPR pledge" ].sample
      )
    end

    # Taxes - quarterly estimated payments (Jan, Apr, Jun, Sep)
    if [ 1, 4, 6, 9 ].include?(month_num)
      create_transaction(
        account: accounts[:main_checking],
        category: expense_categories["taxes"],
        amount: 1500.00,
        transaction_type: "expense",
        date: month_start + 15.days,
        description: "Quarterly estimated tax payment"
      )
    end

    # Education - occasional courses
    if rand < 0.15
      create_transaction(
        account: accounts[:main_checking],
        category: expense_categories["education"],
        amount: (100 + rand * 300).round(2),
        transaction_type: "expense",
        date: month_start + (5 + rand(20)).days,
        description: [ "Online course", "Udemy course", "Professional certification", "Workshop" ].sample
      )
    end

    # Cash transactions - ATM and small purchases
    create_transaction(
      account: accounts[:wallet],
      category: income_categories["other income"],
      amount: (100 + rand * 100).round(2),
      transaction_type: "income",
      date: month_start + (1 + rand(5)).days,
      description: "ATM withdrawal"
    )

    # Small cash purchases
    (2 + rand(3)).times do |i|
      create_transaction(
        account: accounts[:wallet],
        category: [ expense_categories["dining"], expense_categories["personal"], expense_categories["entertainment"] ].sample,
        amount: (5 + rand * 25).round(2),
        transaction_type: "expense",
        date: month_start + (3 + i * 5 + rand(4)).days,
        description: [ "Coffee shop", "Food truck", "Street vendor", "Tips", "Parking meter" ].sample
      )
    end

    puts "  Month #{month_start.strftime('%B %Y')}: transactions created"
  end

  # ---------------------------------------------------------------------------
  # Budgets (current month - covering all expense categories)
  # ---------------------------------------------------------------------------
  puts "Creating budgets..."

  # Monthly budgets - for regular recurring expenses
  monthly_budgets = {
    "mortgage" => 1900.00,
    "utilities" => 300.00,
    "groceries" => 600.00,
    "dining" => 300.00,
    "gas" => 150.00,
    "subscriptions" => 75.00
  }

  monthly_budgets.each do |category_name, amount|
    category = expense_categories[category_name]
    next unless category

    Budget.find_or_create_by!(category: category) do |b|
      b.amount = amount
      b.period = "monthly"
    end
  end

  # Yearly budgets - for irregular/annual expenses
  yearly_budgets = {
    "travel" => 3600.00,        # $300/month equivalent - vacations
    "gifts" => 1500.00,         # Holidays, birthdays
    "charity" => 1200.00,       # Charitable donations
    "taxes" => 6000.00,         # Estimated tax payments
    "education" => 1500.00,     # Courses, certifications
    "clothing" => 2400.00,      # $200/month equivalent
    "entertainment" => 2400.00, # $200/month equivalent - concerts, events
    "healthcare" => 4200.00,    # $350/month equivalent - includes deductibles
    "insurance" => 1800.00,     # $150/month equivalent - various policies
    "transportation" => 1800.00, # $150/month equivalent - repairs, maintenance
    "maintenance" => 2400.00,   # $200/month equivalent - home repairs
    "personal" => 1800.00,      # $150/month equivalent
    "fees" => 600.00,           # $50/month equivalent - bank fees, etc.
    "other expense" => 1200.00  # $100/month equivalent - miscellaneous
  }

  yearly_budgets.each do |category_name, amount|
    category = expense_categories[category_name]
    next unless category

    Budget.find_or_create_by!(category: category) do |b|
      b.amount = amount
      b.period = "yearly"
      b.start_date = today.beginning_of_year
    end
  end

  # ---------------------------------------------------------------------------
  # Asset Valuations (12 months of historical values for tracking)
  # ---------------------------------------------------------------------------
  puts "Creating asset valuations..."

  # Find assets and create historical valuations
  primary_residence = Asset.find_by(name: "Primary Residence")
  if primary_residence
    12.times do |i|
      valuation_date = today - (i + 1).months
      AssetValuation.find_or_create_by!(asset: primary_residence, date: valuation_date) do |v|
        # House appreciated ~5% over year
        v.value = 450000 - ((i + 1) * 1800)
      end
    end
  end

  stock_portfolio = Asset.find_by(name: "Stock Portfolio")
  if stock_portfolio
    12.times do |i|
      valuation_date = today - (i + 1).months
      AssetValuation.find_or_create_by!(asset: stock_portfolio, date: valuation_date) do |v|
        # Stocks grew ~15% over year with fluctuation
        base = 45000 - ((i + 1) * 450)
        v.value = (base + (rand - 0.5) * 2000).round(2)
      end
    end
  end

  bitcoin = Asset.find_by(name: "Bitcoin Holdings")
  if bitcoin
    12.times do |i|
      valuation_date = today - (i + 1).months
      AssetValuation.find_or_create_by!(asset: bitcoin, date: valuation_date) do |v|
        # Crypto very volatile - can swing 30%+ either way
        base = 12500 - ((i + 1) * 200)
        v.value = (base * (0.7 + rand * 0.6)).round(2)
      end
    end
  end

  retirement = Asset.find_by(name: "401(k)")
  if retirement
    12.times do |i|
      valuation_date = today - (i + 1).months
      AssetValuation.find_or_create_by!(asset: retirement, date: valuation_date) do |v|
        # Steady growth ~10% per year plus contributions
        v.value = 125000 - ((i + 1) * 1500)
      end
    end
  end

  swiss_fund = Asset.find_by(name: "Swiss Investment Fund")
  if swiss_fund
    12.times do |i|
      valuation_date = today - (i + 1).months
      AssetValuation.find_or_create_by!(asset: swiss_fund, date: valuation_date) do |v|
        # Steady growth ~6% per year
        v.value = 25000 - ((i + 1) * 120)
      end
    end
  end

  home_mortgage = Asset.find_by(name: "Home Mortgage")
  if home_mortgage
    12.times do |i|
      valuation_date = today - (i + 1).months
      AssetValuation.find_or_create_by!(asset: home_mortgage, date: valuation_date) do |v|
        # Mortgage decreases slowly (principal payments)
        v.value = 320000 + ((i + 1) * 400)
      end
    end
  end

  car_value = Asset.find_by(name: "Toyota Camry")
  if car_value
    12.times do |i|
      valuation_date = today - (i + 1).months
      AssetValuation.find_or_create_by!(asset: car_value, date: valuation_date) do |v|
        # Car depreciates ~10% per year
        v.value = 22000 + ((i + 1) * 180)
      end
    end
  end

  car_loan = Asset.find_by(name: "Car Loan")
  if car_loan
    12.times do |i|
      valuation_date = today - (i + 1).months
      AssetValuation.find_or_create_by!(asset: car_loan, date: valuation_date) do |v|
        # Loan balance decreases with payments
        v.value = 15000 + ((i + 1) * 250)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Import Sample Transactions via AI Extraction (demonstrates import feature)
  # ---------------------------------------------------------------------------
  if OllamaService.available?
    puts "\nImporting transactions from sample CSV via AI extraction..."

    csv_path = Rails.root.join("test/fixtures/files/sample_bank_statement.csv")
    if File.exist?(csv_path)
      csv_text = File.read(csv_path)
      account = accounts[:main_checking]

      begin
        extractor = TransactionExtractorService.new(csv_text, account)
        extracted = extractor.extract

        imported_count = 0
        skipped_count = 0

        extracted.each do |txn_data|
          # Check for duplicates using the duplicate hash
          temp_txn = Transaction.new(
            date: txn_data[:date],
            amount: txn_data[:amount],
            description: txn_data[:description]
          )
          temp_txn.send(:calculate_duplicate_hash)

          if Transaction.exists?(duplicate_hash: temp_txn.duplicate_hash)
            skipped_count += 1
            next
          end

          # Find category or fall back to "other income"/"other expense"
          category_id = txn_data[:category_id]
          unless category_id
            fallback = txn_data[:transaction_type] == "income" ? "other income" : "other expense"
            category_id = Category.find_by(name: fallback, category_type: txn_data[:transaction_type])&.id
          end

          Transaction.create!(
            account: account,
            category_id: category_id,
            date: txn_data[:date],
            description: txn_data[:description],
            amount: txn_data[:amount],
            transaction_type: txn_data[:transaction_type]
          )
          imported_count += 1
        end

        puts "  AI extracted #{extracted.length} transactions"
        puts "  Imported: #{imported_count}, Skipped (duplicates): #{skipped_count}"
      rescue TransactionExtractorService::ExtractionError => e
        puts "  AI extraction failed: #{e.message}"
        puts "  Skipping AI import (Ollama may need more time to warm up)"
      end
    else
      puts "  Sample CSV not found, skipping AI import"
    end
  else
    puts "\nSkipping AI import (Ollama not available)"
    puts "  To enable: brew install ollama && ollama pull llama3.1:8b && brew services start ollama"
  end

  puts "\nDevelopment sample data loaded!"
  puts "Summary:"
  puts "  - #{Account.count} accounts"
  puts "  - #{Asset.count} assets/liabilities"
  puts "  - #{Transaction.count} transactions"
  puts "  - #{Budget.count} budgets"
  puts "  - #{AssetValuation.count} asset valuations"
end

puts "\nSeed completed successfully!"

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
%w[salary bonus freelance investment dividends rental refund other_income].each do |name|
  income_categories[name] = Category.find_or_create_by!(name: name, category_type: "income")
end

# Categories - Expense
puts "Creating expense categories..."
expense_categories = {}
%w[rent mortgage utilities groceries dining transportation gas insurance healthcare
   entertainment subscriptions clothing education personal travel gifts charity taxes
   fees maintenance other_expense].each do |name|
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

  # Real Estate group
  Asset.find_or_create_by!(name: "Primary Residence") do |a|
    a.asset_type = asset_types["Property"]
    a.asset_group = asset_groups["Real Estate"]
    a.value = 450000
    a.currency = "USD"
    a.notes = "3BR/2BA house purchased in 2020"
  end

  Asset.find_or_create_by!(name: "Home Mortgage") do |a|
    a.asset_type = asset_types["Mortgage"]
    a.asset_group = asset_groups["Real Estate"]
    a.value = 320000
    a.currency = "USD"
    a.notes = "30-year fixed at 3.5%, started 2020"
  end

  Asset.find_or_create_by!(name: "Vacation Condo") do |a|
    a.asset_type = asset_types["Property"]
    a.asset_group = asset_groups["Real Estate"]
    a.value = 180000
    a.currency = "EUR"
    a.notes = "Studio apartment in Barcelona"
  end

  # Investments group
  Asset.find_or_create_by!(name: "401(k)") do |a|
    a.asset_type = asset_types["Retirement"]
    a.asset_group = asset_groups["Investments"]
    a.value = 125000
    a.currency = "USD"
    a.notes = "Employer-sponsored retirement account"
  end

  Asset.find_or_create_by!(name: "Stock Portfolio") do |a|
    a.asset_type = asset_types["Investment"]
    a.asset_group = asset_groups["Investments"]
    a.value = 45000
    a.currency = "USD"
    a.notes = "Individual stocks and ETFs"
  end

  Asset.find_or_create_by!(name: "Bitcoin Holdings") do |a|
    a.asset_type = asset_types["Crypto"]
    a.asset_group = asset_groups["Investments"]
    a.value = 12500
    a.currency = "USD"
    a.notes = "0.15 BTC"
  end

  Asset.find_or_create_by!(name: "Swiss Investment Fund") do |a|
    a.asset_type = asset_types["Investment"]
    a.asset_group = asset_groups["Investments"]
    a.value = 25000
    a.currency = "CHF"
    a.notes = "UBS managed fund"
  end

  Asset.find_or_create_by!(name: "Student Loans") do |a|
    a.asset_type = asset_types["Student Loan"]
    a.asset_group = asset_groups["Investments"]
    a.value = 28000
    a.currency = "USD"
    a.notes = "Federal student loans, 4.5% interest"
  end

  # Vehicles group
  Asset.find_or_create_by!(name: "Toyota Camry") do |a|
    a.asset_type = asset_types["Vehicle"]
    a.asset_group = asset_groups["Vehicles"]
    a.value = 22000
    a.currency = "USD"
    a.notes = "2022 model, purchased used"
  end

  Asset.find_or_create_by!(name: "Car Loan") do |a|
    a.asset_type = asset_types["Auto Loan"]
    a.asset_group = asset_groups["Vehicles"]
    a.value = 15000
    a.currency = "USD"
    a.notes = "5-year loan at 4.9%"
  end

  # Other Assets group
  Asset.find_or_create_by!(name: "Vintage Watch Collection") do |a|
    a.asset_type = asset_types["Other Asset"]
    a.asset_group = asset_groups["Other Assets"]
    a.value = 8500
    a.currency = "USD"
    a.notes = "Rolex Submariner and Omega Speedmaster"
  end

  Asset.find_or_create_by!(name: "Personal Loan from Family") do |a|
    a.asset_type = asset_types["Personal Loan"]
    a.asset_group = asset_groups["Other Assets"]
    a.value = 5000
    a.currency = "USD"
    a.notes = "Interest-free loan from parents"
  end

  # ---------------------------------------------------------------------------
  # Transactions (variety of income and expenses over past 3 months)
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
  current_month = today.beginning_of_month

  # --- Current Month Transactions ---

  # Income - Salary (twice monthly)
  create_transaction(
    account: accounts[:main_checking],
    category: income_categories["salary"],
    amount: 4250.00,
    transaction_type: "income",
    date: current_month + 14.days,
    description: "Paycheck - Mid Month"
  )

  create_transaction(
    account: accounts[:main_checking],
    category: income_categories["salary"],
    amount: 4250.00,
    transaction_type: "income",
    date: current_month,
    description: "Paycheck - End of Month"
  )

  # Income - Dividends
  create_transaction(
    account: accounts[:brokerage],
    category: income_categories["dividends"],
    amount: 125.50,
    transaction_type: "income",
    date: current_month + 5.days,
    description: "Q4 Dividend Payment - VTI"
  )

  # Income - Freelance
  create_transaction(
    account: accounts[:main_checking],
    category: income_categories["freelance"],
    amount: 850.00,
    transaction_type: "income",
    date: current_month + 10.days,
    description: "Website design project"
  )

  # Euro income - Rental
  create_transaction(
    account: accounts[:euro_checking],
    category: income_categories["rental"],
    amount: 950.00,
    transaction_type: "income",
    date: current_month + 1.day,
    description: "Barcelona condo rental income"
  )

  # Expenses - Housing
  create_transaction(
    account: accounts[:main_checking],
    category: expense_categories["mortgage"],
    amount: 1850.00,
    transaction_type: "expense",
    date: current_month + 1.day,
    description: "Monthly mortgage payment"
  )

  create_transaction(
    account: accounts[:main_checking],
    category: expense_categories["utilities"],
    amount: 185.00,
    transaction_type: "expense",
    date: current_month + 3.days,
    description: "Electric bill"
  )

  create_transaction(
    account: accounts[:main_checking],
    category: expense_categories["utilities"],
    amount: 65.00,
    transaction_type: "expense",
    date: current_month + 4.days,
    description: "Water bill"
  )

  create_transaction(
    account: accounts[:main_checking],
    category: expense_categories["insurance"],
    amount: 125.00,
    transaction_type: "expense",
    date: current_month + 5.days,
    description: "Home insurance"
  )

  # Expenses - Groceries (weekly)
  4.times do |week|
    create_transaction(
      account: accounts[:visa],
      category: expense_categories["groceries"],
      amount: 145.00 + (rand * 30).round(2),
      transaction_type: "expense",
      date: current_month + (week * 7).days,
      description: "Whole Foods"
    )
  end

  # Expenses - Dining
  create_transaction(
    account: accounts[:visa],
    category: expense_categories["dining"],
    amount: 78.50,
    transaction_type: "expense",
    date: current_month + 6.days,
    description: "Birthday dinner at Italian place"
  )

  create_transaction(
    account: accounts[:visa],
    category: expense_categories["dining"],
    amount: 24.00,
    transaction_type: "expense",
    date: current_month + 12.days,
    description: "Lunch with coworkers"
  )

  create_transaction(
    account: accounts[:amex],
    category: expense_categories["dining"],
    amount: 156.00,
    transaction_type: "expense",
    date: current_month + 18.days,
    description: "Anniversary dinner"
  )

  # Expenses - Transportation
  create_transaction(
    account: accounts[:visa],
    category: expense_categories["gas"],
    amount: 52.00,
    transaction_type: "expense",
    date: current_month + 2.days,
    description: "Shell gas station"
  )

  create_transaction(
    account: accounts[:visa],
    category: expense_categories["gas"],
    amount: 48.50,
    transaction_type: "expense",
    date: current_month + 16.days,
    description: "Chevron"
  )

  create_transaction(
    account: accounts[:main_checking],
    category: expense_categories["transportation"],
    amount: 89.00,
    transaction_type: "expense",
    date: current_month + 5.days,
    description: "Car wash and oil change"
  )

  # Expenses - Subscriptions
  create_transaction(
    account: accounts[:visa],
    category: expense_categories["subscriptions"],
    amount: 15.99,
    transaction_type: "expense",
    date: current_month + 1.day,
    description: "Netflix"
  )

  create_transaction(
    account: accounts[:visa],
    category: expense_categories["subscriptions"],
    amount: 10.99,
    transaction_type: "expense",
    date: current_month + 1.day,
    description: "Spotify"
  )

  create_transaction(
    account: accounts[:visa],
    category: expense_categories["subscriptions"],
    amount: 14.99,
    transaction_type: "expense",
    date: current_month + 3.days,
    description: "iCloud Storage"
  )

  create_transaction(
    account: accounts[:amex],
    category: expense_categories["subscriptions"],
    amount: 12.99,
    transaction_type: "expense",
    date: current_month + 8.days,
    description: "New York Times"
  )

  # Expenses - Healthcare
  create_transaction(
    account: accounts[:main_checking],
    category: expense_categories["healthcare"],
    amount: 250.00,
    transaction_type: "expense",
    date: current_month + 10.days,
    description: "Health insurance premium"
  )

  create_transaction(
    account: accounts[:visa],
    category: expense_categories["healthcare"],
    amount: 35.00,
    transaction_type: "expense",
    date: current_month + 15.days,
    description: "Pharmacy - prescriptions"
  )

  # Expenses - Entertainment
  create_transaction(
    account: accounts[:wallet],
    category: expense_categories["entertainment"],
    amount: 45.00,
    transaction_type: "expense",
    date: current_month + 7.days,
    description: "Movie tickets and popcorn"
  )

  create_transaction(
    account: accounts[:amex],
    category: expense_categories["entertainment"],
    amount: 120.00,
    transaction_type: "expense",
    date: current_month + 20.days,
    description: "Concert tickets"
  )

  # Expenses - Personal
  create_transaction(
    account: accounts[:visa],
    category: expense_categories["personal"],
    amount: 65.00,
    transaction_type: "expense",
    date: current_month + 11.days,
    description: "Haircut and grooming"
  )

  # Expenses - Clothing
  create_transaction(
    account: accounts[:amex],
    category: expense_categories["clothing"],
    amount: 189.00,
    transaction_type: "expense",
    date: current_month + 14.days,
    description: "New running shoes"
  )

  # Euro expenses
  create_transaction(
    account: accounts[:euro_checking],
    category: expense_categories["fees"],
    amount: 45.00,
    transaction_type: "expense",
    date: current_month + 5.days,
    description: "Condo HOA fees"
  )

  create_transaction(
    account: accounts[:euro_checking],
    category: expense_categories["maintenance"],
    amount: 120.00,
    transaction_type: "expense",
    date: current_month + 8.days,
    description: "Condo maintenance"
  )

  # CHF transactions
  create_transaction(
    account: accounts[:swiss_savings],
    category: income_categories["investment"],
    amount: 350.00,
    transaction_type: "income",
    date: current_month + 12.days,
    description: "Investment fund interest"
  )

  # Cash transactions
  create_transaction(
    account: accounts[:wallet],
    category: income_categories["other_income"],
    amount: 200.00,
    transaction_type: "income",
    date: current_month,
    description: "ATM withdrawal"
  )

  create_transaction(
    account: accounts[:wallet],
    category: expense_categories["dining"],
    amount: 18.00,
    transaction_type: "expense",
    date: current_month + 3.days,
    description: "Food truck lunch"
  )

  create_transaction(
    account: accounts[:wallet],
    category: expense_categories["personal"],
    amount: 12.00,
    transaction_type: "expense",
    date: current_month + 9.days,
    description: "Tips"
  )

  # --- Previous Month Transactions ---
  prev_month = (current_month - 1.month)

  # Salary
  create_transaction(
    account: accounts[:main_checking],
    category: income_categories["salary"],
    amount: 4250.00,
    transaction_type: "income",
    date: prev_month + 14.days,
    description: "Paycheck - Mid Month"
  )

  create_transaction(
    account: accounts[:main_checking],
    category: income_categories["salary"],
    amount: 4250.00,
    transaction_type: "income",
    date: prev_month,
    description: "Paycheck - End of Month"
  )

  # Bonus!
  create_transaction(
    account: accounts[:main_checking],
    category: income_categories["bonus"],
    amount: 2500.00,
    transaction_type: "income",
    date: prev_month + 20.days,
    description: "Year-end performance bonus"
  )

  # Mortgage and utilities
  create_transaction(
    account: accounts[:main_checking],
    category: expense_categories["mortgage"],
    amount: 1850.00,
    transaction_type: "expense",
    date: prev_month + 1.day,
    description: "Monthly mortgage payment"
  )

  create_transaction(
    account: accounts[:main_checking],
    category: expense_categories["utilities"],
    amount: 210.00,
    transaction_type: "expense",
    date: prev_month + 3.days,
    description: "Electric bill (higher - winter)"
  )

  # Groceries
  4.times do |week|
    create_transaction(
      account: accounts[:visa],
      category: expense_categories["groceries"],
      amount: 155.00 + (rand * 25).round(2),
      transaction_type: "expense",
      date: prev_month + (week * 7).days,
      description: "Whole Foods"
    )
  end

  # Travel expense
  create_transaction(
    account: accounts[:amex],
    category: expense_categories["travel"],
    amount: 450.00,
    transaction_type: "expense",
    date: prev_month + 10.days,
    description: "Flight tickets - Holiday trip"
  )

  create_transaction(
    account: accounts[:amex],
    category: expense_categories["travel"],
    amount: 380.00,
    transaction_type: "expense",
    date: prev_month + 12.days,
    description: "Hotel booking"
  )

  # Gifts (holiday season)
  create_transaction(
    account: accounts[:amex],
    category: expense_categories["gifts"],
    amount: 250.00,
    transaction_type: "expense",
    date: prev_month + 15.days,
    description: "Holiday gifts for family"
  )

  create_transaction(
    account: accounts[:visa],
    category: expense_categories["gifts"],
    amount: 85.00,
    transaction_type: "expense",
    date: prev_month + 18.days,
    description: "Gift for friend's birthday"
  )

  # Charity
  create_transaction(
    account: accounts[:main_checking],
    category: expense_categories["charity"],
    amount: 100.00,
    transaction_type: "expense",
    date: prev_month + 20.days,
    description: "Year-end charitable donation"
  )

  # Euro rental income
  create_transaction(
    account: accounts[:euro_checking],
    category: income_categories["rental"],
    amount: 950.00,
    transaction_type: "income",
    date: prev_month + 1.day,
    description: "Barcelona condo rental income"
  )

  # --- Two Months Ago Transactions ---
  two_months_ago = (current_month - 2.months)

  # Salary
  create_transaction(
    account: accounts[:main_checking],
    category: income_categories["salary"],
    amount: 4250.00,
    transaction_type: "income",
    date: two_months_ago + 14.days,
    description: "Paycheck - Mid Month"
  )

  create_transaction(
    account: accounts[:main_checking],
    category: income_categories["salary"],
    amount: 4250.00,
    transaction_type: "income",
    date: two_months_ago,
    description: "Paycheck - End of Month"
  )

  # Refund!
  create_transaction(
    account: accounts[:visa],
    category: income_categories["refund"],
    amount: 89.99,
    transaction_type: "income",
    date: two_months_ago + 8.days,
    description: "Amazon return refund"
  )

  # Mortgage
  create_transaction(
    account: accounts[:main_checking],
    category: expense_categories["mortgage"],
    amount: 1850.00,
    transaction_type: "expense",
    date: two_months_ago + 1.day,
    description: "Monthly mortgage payment"
  )

  # Education
  create_transaction(
    account: accounts[:main_checking],
    category: expense_categories["education"],
    amount: 299.00,
    transaction_type: "expense",
    date: two_months_ago + 5.days,
    description: "Online course - AWS certification"
  )

  # Taxes
  create_transaction(
    account: accounts[:main_checking],
    category: expense_categories["taxes"],
    amount: 450.00,
    transaction_type: "expense",
    date: two_months_ago + 15.days,
    description: "Quarterly estimated tax payment"
  )

  # Maintenance
  create_transaction(
    account: accounts[:main_checking],
    category: expense_categories["maintenance"],
    amount: 275.00,
    transaction_type: "expense",
    date: two_months_ago + 20.days,
    description: "HVAC maintenance"
  )

  # Fees
  create_transaction(
    account: accounts[:main_checking],
    category: expense_categories["fees"],
    amount: 35.00,
    transaction_type: "expense",
    date: two_months_ago + 10.days,
    description: "Bank wire transfer fee"
  )

  # Euro rental
  create_transaction(
    account: accounts[:euro_checking],
    category: income_categories["rental"],
    amount: 950.00,
    transaction_type: "income",
    date: two_months_ago + 1.day,
    description: "Barcelona condo rental income"
  )

  # ---------------------------------------------------------------------------
  # Budgets (current month - covering all expense categories)
  # ---------------------------------------------------------------------------
  puts "Creating budgets..."

  current_year = today.year
  current_month_num = today.month

  budgets = {
    "mortgage" => 1900.00,
    "utilities" => 300.00,
    "groceries" => 600.00,
    "dining" => 300.00,
    "transportation" => 150.00,
    "gas" => 150.00,
    "insurance" => 150.00,
    "healthcare" => 350.00,
    "entertainment" => 200.00,
    "subscriptions" => 75.00,
    "clothing" => 150.00,
    "education" => 100.00,
    "personal" => 150.00,
    "travel" => 200.00,
    "gifts" => 100.00,
    "charity" => 100.00,
    "taxes" => 500.00,
    "fees" => 50.00,
    "maintenance" => 200.00,
    "other_expense" => 100.00
  }

  budgets.each do |category_name, amount|
    category = expense_categories[category_name]
    next unless category

    Budget.find_or_create_by!(
      category: category,
      year: current_year,
      month: current_month_num
    ) do |b|
      b.amount = amount
    end
  end

  # Also create budgets for previous month
  prev_month_num = prev_month.month
  prev_year = prev_month.year

  budgets.each do |category_name, amount|
    category = expense_categories[category_name]
    next unless category

    Budget.find_or_create_by!(
      category: category,
      year: prev_year,
      month: prev_month_num
    ) do |b|
      b.amount = amount
    end
  end

  # ---------------------------------------------------------------------------
  # Asset Valuations (historical values for tracking)
  # ---------------------------------------------------------------------------
  puts "Creating asset valuations..."

  # Find assets and create historical valuations
  primary_residence = Asset.find_by(name: "Primary Residence")
  if primary_residence
    3.times do |i|
      valuation_date = today - (i + 1).months
      AssetValuation.find_or_create_by!(asset: primary_residence, date: valuation_date) do |v|
        # House appreciated slightly
        v.value = 450000 - ((i + 1) * 2500)
      end
    end
  end

  stock_portfolio = Asset.find_by(name: "Stock Portfolio")
  if stock_portfolio
    3.times do |i|
      valuation_date = today - (i + 1).months
      AssetValuation.find_or_create_by!(asset: stock_portfolio, date: valuation_date) do |v|
        # Stocks fluctuated
        v.value = 45000 - ((i + 1) * 1500) + (rand * 1000).round(2)
      end
    end
  end

  bitcoin = Asset.find_by(name: "Bitcoin Holdings")
  if bitcoin
    3.times do |i|
      valuation_date = today - (i + 1).months
      AssetValuation.find_or_create_by!(asset: bitcoin, date: valuation_date) do |v|
        # Crypto volatile
        v.value = 12500 + ((rand - 0.5) * 3000).round(2)
      end
    end
  end

  retirement = Asset.find_by(name: "401(k)")
  if retirement
    3.times do |i|
      valuation_date = today - (i + 1).months
      AssetValuation.find_or_create_by!(asset: retirement, date: valuation_date) do |v|
        # Steady growth
        v.value = 125000 - ((i + 1) * 2000)
      end
    end
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

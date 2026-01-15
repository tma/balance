# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Currencies (ISO 4217)
[
  { code: "USD", default: true },
  { code: "EUR", default: false },
  { code: "CHF", default: false }
].each do |attrs|
  Currency.find_or_create_by!(code: attrs[:code]) do |currency|
    currency.default = attrs[:default]
  end
end

# Account Types
%w[checking savings credit cash investment].each do |name|
  AccountType.find_or_create_by!(name: name)
end

# Asset Types
[
  { name: "property", is_liability: false },
  { name: "vehicle", is_liability: false },
  { name: "investment", is_liability: false },
  { name: "retirement", is_liability: false },
  { name: "crypto", is_liability: false },
  { name: "other_asset", is_liability: false },
  { name: "mortgage", is_liability: true },
  { name: "auto_loan", is_liability: true },
  { name: "student_loan", is_liability: true },
  { name: "credit_card_debt", is_liability: true },
  { name: "personal_loan", is_liability: true },
  { name: "other_liability", is_liability: true }
].each do |attrs|
  AssetType.find_or_create_by!(name: attrs[:name]) do |at|
    at.is_liability = attrs[:is_liability]
  end
end

# Categories - Income
%w[salary bonus freelance investment dividends rental refund other_income].each do |name|
  Category.find_or_create_by!(name: name, category_type: "income")
end

# Categories - Expense
%w[rent mortgage utilities groceries dining transportation gas insurance healthcare
   entertainment subscriptions clothing education personal travel gifts charity taxes
   fees maintenance other_expense].each do |name|
  Category.find_or_create_by!(name: name, category_type: "expense")
end

puts "Seed data loaded successfully!"

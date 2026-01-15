json.extract! budget, :id, :category_id, :amount, :month, :year, :created_at, :updated_at
json.url budget_url(budget, format: :json)

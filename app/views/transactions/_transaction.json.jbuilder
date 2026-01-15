json.extract! transaction, :id, :account_id, :category_id, :amount, :transaction_type, :date, :description, :created_at, :updated_at
json.url transaction_url(transaction, format: :json)

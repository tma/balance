json.extract! account, :id, :name, :account_type_id, :balance, :currency, :created_at, :updated_at
json.url account_url(account, format: :json)

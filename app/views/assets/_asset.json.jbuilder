json.extract! asset, :id, :name, :asset_type_id, :value, :currency, :notes, :created_at, :updated_at
json.url asset_url(asset, format: :json)

# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_01_27_190113) do
  create_table "account_types", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "invert_amounts_on_import", default: false, null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "accounts", force: :cascade do |t|
    t.integer "account_type_id", null: false
    t.decimal "balance"
    t.decimal "balance_in_default_currency"
    t.datetime "created_at", null: false
    t.text "csv_column_mapping"
    t.string "currency"
    t.decimal "exchange_rate"
    t.text "import_ignore_patterns"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["account_type_id"], name: "index_accounts_on_account_type_id"
  end

  create_table "asset_groups", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
  end

  create_table "asset_types", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_liability"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "asset_valuations", force: :cascade do |t|
    t.integer "asset_id", null: false
    t.datetime "created_at", null: false
    t.date "date"
    t.decimal "exchange_rate"
    t.string "formula"
    t.datetime "updated_at", null: false
    t.decimal "value"
    t.decimal "value_in_default_currency"
    t.index ["asset_id"], name: "index_asset_valuations_on_asset_id"
  end

  create_table "assets", force: :cascade do |t|
    t.boolean "archived", default: false, null: false
    t.integer "asset_group_id", null: false
    t.integer "asset_type_id", null: false
    t.datetime "created_at", null: false
    t.string "currency"
    t.decimal "exchange_rate"
    t.string "name"
    t.text "notes"
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.decimal "value"
    t.decimal "value_in_default_currency"
    t.index ["archived"], name: "index_assets_on_archived"
    t.index ["asset_group_id"], name: "index_assets_on_asset_group_id"
    t.index ["asset_type_id"], name: "index_assets_on_asset_type_id"
  end

  create_table "broker_connections", force: :cascade do |t|
    t.string "account_id", null: false
    t.integer "broker_type", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "flex_query_id", null: false
    t.string "flex_token", null: false
    t.text "last_sync_error"
    t.datetime "last_synced_at"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["broker_type", "account_id"], name: "index_broker_connections_on_broker_type_and_account_id", unique: true
  end

  create_table "broker_positions", force: :cascade do |t|
    t.integer "asset_id"
    t.integer "broker_connection_id", null: false
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.string "currency"
    t.string "description"
    t.string "exchange"
    t.decimal "last_quantity"
    t.datetime "last_synced_at"
    t.decimal "last_value"
    t.string "symbol", null: false
    t.datetime "updated_at", null: false
    t.index ["asset_id"], name: "index_broker_positions_on_asset_id"
    t.index ["broker_connection_id", "symbol"], name: "index_broker_positions_on_broker_connection_id_and_symbol", unique: true
    t.index ["broker_connection_id"], name: "index_broker_positions_on_broker_connection_id"
  end

  create_table "budgets", force: :cascade do |t|
    t.decimal "amount"
    t.integer "category_id", null: false
    t.datetime "created_at", null: false
    t.string "period", default: "monthly", null: false
    t.date "start_date"
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_budgets_on_category_id", unique: true
  end

  create_table "categories", force: :cascade do |t|
    t.string "category_type"
    t.datetime "created_at", null: false
    t.text "match_patterns"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "currencies", force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", null: false
    t.boolean "default", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_currencies_on_code", unique: true
  end

  create_table "imports", force: :cascade do |t|
    t.integer "account_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.integer "extracted_count"
    t.text "extracted_data"
    t.string "file_content_type"
    t.binary "file_data"
    t.string "original_filename"
    t.string "progress"
    t.string "progress_message"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.integer "transactions_count", default: 0
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_imports_on_account_id"
    t.index ["status"], name: "index_imports_on_status"
  end

  create_table "position_valuations", force: :cascade do |t|
    t.integer "broker_position_id", null: false
    t.datetime "created_at", null: false
    t.string "currency", null: false
    t.date "date", null: false
    t.decimal "exchange_rate"
    t.decimal "quantity", precision: 15, scale: 4
    t.datetime "updated_at", null: false
    t.decimal "value", precision: 15, scale: 2
    t.decimal "value_in_default_currency"
    t.index ["broker_position_id", "date"], name: "index_position_valuations_on_broker_position_id_and_date", unique: true
    t.index ["broker_position_id"], name: "index_position_valuations_on_broker_position_id"
  end

  create_table "transactions", force: :cascade do |t|
    t.integer "account_id", null: false
    t.decimal "amount"
    t.decimal "amount_in_default_currency"
    t.integer "category_id", null: false
    t.datetime "created_at", null: false
    t.date "date"
    t.string "description"
    t.string "duplicate_hash"
    t.decimal "exchange_rate"
    t.integer "import_id"
    t.string "transaction_type"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["duplicate_hash"], name: "index_transactions_on_duplicate_hash"
    t.index ["import_id"], name: "index_transactions_on_import_id"
  end

  add_foreign_key "accounts", "account_types"
  add_foreign_key "asset_valuations", "assets"
  add_foreign_key "assets", "asset_groups"
  add_foreign_key "assets", "asset_types"
  add_foreign_key "broker_positions", "assets"
  add_foreign_key "broker_positions", "broker_connections"
  add_foreign_key "budgets", "categories"
  add_foreign_key "imports", "accounts"
  add_foreign_key "position_valuations", "broker_positions"
  add_foreign_key "transactions", "accounts"
  add_foreign_key "transactions", "categories"
  add_foreign_key "transactions", "imports"
end

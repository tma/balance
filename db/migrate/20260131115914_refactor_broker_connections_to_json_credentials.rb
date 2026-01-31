class RefactorBrokerConnectionsToJsonCredentials < ActiveRecord::Migration[8.1]
  def up
    # Step 1: Add new credentials column
    add_column :broker_connections, :credentials, :text

    # Step 2: Migrate existing IBKR data to JSON credentials
    # Define inline model that matches OLD schema (before migration)
    old_model = Class.new(ApplicationRecord) do
      self.table_name = "broker_connections"
      encrypts :flex_token  # Only flex_token was encrypted in old schema
    end
    old_model.reset_column_information

    # Define inline model for NEW schema (credentials encrypted)
    new_model = Class.new(ApplicationRecord) do
      self.table_name = "broker_connections"
      encrypts :credentials
    end
    new_model.reset_column_information

    old_model.find_each do |conn|
      # Read using old model (decrypts flex_token)
      token = conn.flex_token
      query_id = conn.flex_query_id

      if token.present? || query_id.present?
        # Write using new model (encrypts credentials)
        new_record = new_model.find(conn.id)
        new_record.credentials = { "flex_token" => token, "flex_query_id" => query_id }.to_json
        new_record.save!(validate: false)
      end
    end

    # Step 3: Remove old columns and index
    remove_index :broker_connections, [ :broker_type, :account_id ] if index_exists?(:broker_connections, [ :broker_type, :account_id ])
    remove_column :broker_connections, :account_id if column_exists?(:broker_connections, :account_id)
    remove_column :broker_connections, :flex_token if column_exists?(:broker_connections, :flex_token)
    remove_column :broker_connections, :flex_query_id if column_exists?(:broker_connections, :flex_query_id)
  end

  def down
    # Restore old columns
    add_column :broker_connections, :account_id, :string
    add_column :broker_connections, :flex_token, :string
    add_column :broker_connections, :flex_query_id, :string

    # Define inline model for reading NEW schema (credentials encrypted)
    new_model = Class.new(ApplicationRecord) do
      self.table_name = "broker_connections"
      encrypts :credentials
    end
    new_model.reset_column_information

    # Define inline model for writing OLD schema (flex_token encrypted)
    old_model = Class.new(ApplicationRecord) do
      self.table_name = "broker_connections"
      encrypts :flex_token
    end
    old_model.reset_column_information

    new_model.find_each do |conn|
      next unless conn.credentials.present?
      creds = JSON.parse(conn.credentials) rescue {}

      old_record = old_model.find(conn.id)
      old_record.flex_token = creds["flex_token"]
      old_record.flex_query_id = creds["flex_query_id"]
      old_record.account_id = "U0000000"  # Placeholder since we don't have the original
      old_record.save!(validate: false)
    end

    # Restore index
    add_index :broker_connections, [ :broker_type, :account_id ], unique: true

    # Remove credentials column
    remove_column :broker_connections, :credentials
  end
end

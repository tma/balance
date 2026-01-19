# frozen_string_literal: true

# Configure Active Record Encryption for encrypted model attributes (e.g., IbkrConnection.flex_token)
#
# In production, set these environment variables:
#   ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
#   ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
#   ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
#
# Generate new keys with: bin/rails db:encryption:init

Rails.application.configure do
  config.active_record.encryption.primary_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY") {
    # Development/test fallback - NOT for production use
    "dev-primary-key-not-for-production"
  }

  config.active_record.encryption.deterministic_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY") {
    # Development/test fallback - NOT for production use
    "dev-deterministic-key-not-for-prod"
  }

  config.active_record.encryption.key_derivation_salt = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT") {
    # Development/test fallback - NOT for production use
    "dev-key-derivation-salt-not-prod"
  }
end

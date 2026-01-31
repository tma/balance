class BrokerConnection < ApplicationRecord
  has_many :broker_positions, dependent: :destroy

  # Broker types - extendable for future brokers
  enum :broker_type, { ibkr: 0, manual: 1 }

  # Encrypt credentials JSON
  encrypts :credentials

  validates :name, presence: true

  # IBKR-specific validations
  validate :validate_ibkr_credentials, if: :ibkr?

  # Accessor methods for credentials stored in JSON
  def flex_token
    credentials_hash["flex_token"]
  end

  def flex_token=(value)
    self.credentials = credentials_hash.merge("flex_token" => value).to_json
  end

  def flex_query_id
    credentials_hash["flex_query_id"]
  end

  def flex_query_id=(value)
    self.credentials = credentials_hash.merge("flex_query_id" => value).to_json
  end

  # Display name for the broker type
  def broker_type_name
    case broker_type
    when "ibkr" then "Interactive Brokers"
    when "manual" then "Manual"
    else broker_type.titleize
    end
  end

  def mapped_positions
    broker_positions.where.not(asset_id: nil)
  end

  def unmapped_positions
    broker_positions.where(asset_id: nil)
  end

  def sync_status
    return :never if last_synced_at.nil?
    return :error if last_sync_error.present?
    return :behind if missing_sync_days.positive?

    :ok
  end

  def missing_sync_days
    return 0 if last_synced_at.nil?

    BrokerSyncBackfillService.missing_dates_for(self).count
  end

  # Human-readable sync status for display
  def sync_status_label
    case sync_status
    when :never
      "Never synced"
    when :error
      "Failed: #{last_sync_error.to_s.truncate(50)}"
    when :behind
      "#{missing_sync_days} days behind"
    else
      "Synced"
    end
  end

  private

  def credentials_hash
    return {} if credentials.blank?
    JSON.parse(credentials)
  rescue JSON::ParserError
    {}
  end

  def validate_ibkr_credentials
    errors.add(:flex_token, "can't be blank") if flex_token.blank?
    errors.add(:flex_query_id, "can't be blank") if flex_query_id.blank?
  end
end

class BrokerConnection < ApplicationRecord
  has_many :broker_positions, dependent: :destroy

  # Broker types - extendable for future brokers
  enum :broker_type, { ibkr: 0 }

  # Encrypt sensitive credentials
  encrypts :flex_token

  validates :account_id, presence: true
  validates :account_id, uniqueness: { scope: :broker_type }
  validates :name, presence: true
  validates :flex_token, presence: true, if: :ibkr?
  validates :flex_query_id, presence: true, if: :ibkr?

  def mapped_positions
    broker_positions.where.not(asset_id: nil)
  end

  def unmapped_positions
    broker_positions.where(asset_id: nil)
  end

  def sync_status
    return :never if last_synced_at.nil?
    return :error if last_sync_error.present?
    return :behind if days_behind && days_behind > 1

    :ok
  end

  # Number of days since last successful sync date
  # Returns nil if never synced
  def days_behind
    return nil if last_sync_date.nil?

    (Date.current - last_sync_date).to_i
  end

  # Human-readable sync status for display
  def sync_status_label
    case sync_status
    when :never
      "Never synced"
    when :error
      "Failed: #{last_sync_error.to_s.truncate(50)}"
    when :behind
      "#{days_behind} days behind"
    else
      "Synced"
    end
  end

  # Display name for the broker type
  def broker_type_name
    case broker_type
    when "ibkr" then "Interactive Brokers"
    else broker_type.titleize
    end
  end
end

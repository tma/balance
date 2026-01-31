class BrokerPosition < ApplicationRecord
  belongs_to :broker_connection
  belongs_to :asset, optional: true
  has_many :position_valuations, dependent: :destroy

  # Map common crypto symbols to CoinGecko IDs
  COINGECKO_SYMBOL_MAP = {
    "BTC" => "bitcoin",
    "ETH" => "ethereum",
    "SOL" => "solana",
    "BCH" => "bitcoin-cash",
    "LTC" => "litecoin",
    "ADA" => "cardano",
    "LINK" => "chainlink",
    "DOGE" => "dogecoin",
    "XRP" => "ripple",
    "AVAX" => "avalanche-2",
    "SUI" => "sui"
  }.freeze

  validates :symbol, presence: true
  validates :symbol, uniqueness: { scope: :broker_connection_id }

  scope :mapped, -> { where.not(asset_id: nil) }
  scope :unmapped, -> { where(asset_id: nil) }
  scope :open, -> { where(closed_at: nil) }
  scope :closed, -> { where.not(closed_at: nil) }

  def mapped?
    asset_id.present?
  end

  def closed?
    closed_at.present?
  end

  def open?
    !closed?
  end

  def default_currency
    Currency.default_code
  end

  # Get the CoinGecko ID for this symbol (if it's a supported crypto)
  def coingecko_id
    COINGECKO_SYMBOL_MAP[symbol&.upcase]
  end

  # Check if this position is a supported crypto
  def crypto_position?
    coingecko_id.present?
  end

  # Get the last value converted to default currency from the most recent valuation
  def last_value_in_default_currency
    position_valuations.order(date: :desc).first&.value_in_default_currency
  end

  # Syncs the position value to the mapped asset
  def sync_to_asset!
    return unless mapped? && last_value.present?

    asset.sync_from_broker_positions!
  end

  # Record a historical valuation for this position
  def record_valuation!(date: Date.current)
    return unless last_value.present? && last_quantity.present?

    valuation = position_valuations.find_or_initialize_by(date: date)
    valuation.update!(
      quantity: last_quantity,
      value: last_value,
      currency: currency
    )
    valuation
  end

  # Mark position as closed (sold/transferred out)
  # Sets value to 0 and records a final valuation
  def close!(date: Date.current)
    return if closed?

    update!(
      closed_at: Time.current,
      last_value: 0,
      last_quantity: 0
    )

    # Record final zero valuation
    record_valuation!(date: date)

    # Update mapped asset to reflect the closure
    sync_to_asset! if mapped?
  end

  # Reopen a closed position (if it reappears in broker)
  def reopen!
    return unless closed?

    update!(closed_at: nil)
  end
end

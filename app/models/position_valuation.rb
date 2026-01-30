class PositionValuation < ApplicationRecord
  belongs_to :broker_position

  # Virtual attributes for IBKR-provided FX rate (not persisted)
  # Used to pass through the broker's exchange rate when base currencies match
  attr_accessor :fx_rate_to_base, :ibkr_base_currency

  validates :date, presence: true
  validates :date, uniqueness: { scope: :broker_position_id }
  validates :currency, presence: true
  validates :value, numericality: true, allow_nil: true
  validates :quantity, numericality: true, allow_nil: true

  scope :on_date, ->(date) { where(date: date) }
  scope :recent, ->(limit = 30) { order(date: :desc).limit(limit) }
  scope :needs_exchange_rate, -> { where(exchange_rate: nil).where.not(currency: Currency.default&.code) }

  before_save :calculate_default_currency_value

  def default_currency
    Currency.default_code
  end

  private

  def calculate_default_currency_value
    return unless value.present?

    default_curr = default_currency
    if currency == default_curr
      self.exchange_rate = 1.0
      self.value_in_default_currency = value
    else
      rate = determine_exchange_rate(default_curr)
      if rate.nil?
        Rails.logger.warn "Exchange rate unavailable for #{currency}->#{default_curr}, skipping conversion for position valuation"
        return
      end
      self.exchange_rate = rate
      self.value_in_default_currency = (value * exchange_rate).round(2)
    end
  end

  # Determine the exchange rate to use:
  # 1. If IBKR provided fxRateToBase and their base currency matches our default, use it
  # 2. Otherwise, fetch from ExchangeRateService with the valuation date
  def determine_exchange_rate(default_curr)
    # Use IBKR's rate if their base currency matches our default currency
    if fx_rate_to_base.present? && ibkr_base_currency == default_curr
      return fx_rate_to_base
    end

    # Fall back to external exchange rate service with historical date
    ExchangeRateService.rate(currency, default_curr, date: date)
  end
end

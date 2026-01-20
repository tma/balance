class PositionValuation < ApplicationRecord
  belongs_to :broker_position

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
    Currency.default&.code || "USD"
  end

  private

  def calculate_default_currency_value
    return unless value.present?

    default_curr = default_currency
    if currency == default_curr
      self.exchange_rate = 1.0
      self.value_in_default_currency = value
    else
      rate = ExchangeRateService.rate(currency, default_curr)
      if rate.nil?
        Rails.logger.warn "Exchange rate unavailable for #{currency}->#{default_curr}, skipping conversion for position valuation"
        return
      end
      self.exchange_rate = rate
      self.value_in_default_currency = (value * exchange_rate).round(2)
    end
  end
end

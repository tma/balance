class Asset < ApplicationRecord
  belongs_to :asset_type
  belongs_to :asset_group
  has_many :asset_valuations, dependent: :destroy
  has_many :broker_positions, dependent: :nullify

  # Allow setting a custom date for valuation creation (defaults to current date)
  attr_accessor :valuation_date

  validates :name, presence: true
  validates :currency, presence: true
  validates :value, numericality: true

  validate :currency_must_exist
  validate :currency_cannot_change, on: :update

  default_scope { order(:position, :name) }

  scope :by_currency, ->(code) { where(currency: code) }
  scope :assets_only, -> { joins(:asset_type).where(asset_types: { is_liability: false }) }
  scope :liabilities_only, -> { joins(:asset_type).where(asset_types: { is_liability: true }) }
  scope :with_broker, -> { joins(:broker_positions).distinct }

  attribute :value, :decimal, default: 0

  before_save :calculate_default_currency_value
  after_save :create_valuation_if_value_changed

  def default_currency
    Currency.default&.code || "USD"
  end

  def has_broker?
    broker_positions.any?
  end

  # Calculate total value from all broker positions, converted to asset currency
  def total_broker_value
    # Reload to get fresh data from database
    positions = broker_positions.reload
    return nil if positions.empty?

    positions.sum do |position|
      next 0 unless position.last_value.present?

      if position.currency == currency
        position.last_value
      else
        ExchangeRateService.convert(position.last_value, position.currency, currency)
      end
    end
  end

  # Sync value from broker positions
  # Creates/updates a valuation for end of current month
  def sync_from_broker_positions!
    total = total_broker_value
    return unless total.present? && total > 0

    date = Date.current.end_of_month

    # Update asset value
    self.value = total
    calculate_default_currency_value
    save!

    # Always create/update valuation for the month, even if value unchanged
    valuation = asset_valuations.find_or_initialize_by(date: date)
    valuation.update!(
      value: value,
      value_in_default_currency: value_in_default_currency,
      exchange_rate: exchange_rate
    )
  end

  private

  def currency_must_exist
    return if currency.blank?
    errors.add(:currency, "is not a valid currency") unless Currency.exists?(code: currency)
  end

  def currency_cannot_change
    if currency_changed? && currency_was.present?
      errors.add(:currency, "cannot be changed after creation")
    end
  end

  def calculate_default_currency_value
    default_curr = default_currency
    if currency == default_curr
      self.exchange_rate = 1.0
      self.value_in_default_currency = value
    else
      self.exchange_rate = ExchangeRateService.rate(currency, default_curr)
      self.value_in_default_currency = (value * exchange_rate).round(2)
    end
  end

  def create_valuation_if_value_changed
    return unless saved_change_to_value?

    date = valuation_date || Date.current
    valuation = asset_valuations.find_or_initialize_by(date: date)
    valuation.update!(
      value: value,
      value_in_default_currency: value_in_default_currency,
      exchange_rate: exchange_rate
    )
  end
end

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
  scope :active, -> { where(archived: false) }
  scope :archived, -> { where(archived: true) }
  scope :needs_exchange_rate, -> { where(exchange_rate: nil).where.not(currency: Currency.default&.code) }

  attribute :value, :decimal, default: 0

  before_save :calculate_default_currency_value
  after_save :create_valuation_if_value_changed

  def default_currency
    Currency.default&.code || "USD"
  end

  def has_broker?
    broker_positions.open.any?
  end

  def archive!
    if has_broker?
      errors.add(:base, "Cannot archive asset with open broker positions")
      raise ActiveRecord::RecordInvalid, self
    end
    update!(archived: true)
  end

  def unarchive!
    update!(archived: false)
  end

  # Calculate total value from all open broker positions, converted to asset currency
  # Returns nil if positions exist but conversion fails
  def total_broker_value
    # Only consider open positions (not closed/sold)
    positions = broker_positions.open.reload
    return nil if positions.empty?

    total = 0
    positions.each do |position|
      next unless position.last_value.present?

      if position.currency == currency
        total += position.last_value
      else
        converted = ExchangeRateService.convert(position.last_value, position.currency, currency, date: Date.current)
        return nil if converted.nil? # Can't calculate total without all rates
        total += converted
      end
    end
    total
  end

  # Sync value from broker positions
  # Creates/updates a valuation for end of current month
  def sync_from_broker_positions!
    total = total_broker_value

    # If no open positions or total is 0, set to 0
    if total.nil? || total <= 0
      return if value == 0 # No change needed
      total = 0
    end

    date = Date.current.end_of_month

    # Update asset value (round to whole numbers to avoid form change detection issues)
    self.value = total.round(0)
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
      rate = ExchangeRateService.rate(currency, default_curr, date: Date.current)
      if rate.nil?
        Rails.logger.warn "Exchange rate unavailable for #{currency}->#{default_curr}, skipping conversion for asset"
        return
      end
      self.exchange_rate = rate
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

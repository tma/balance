class Asset < ApplicationRecord
  belongs_to :asset_type
  belongs_to :asset_group
  has_many :asset_valuations, dependent: :destroy

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

  attribute :value, :decimal, default: 0

  before_save :calculate_default_currency_value
  after_save :create_valuation_if_value_changed

  def default_currency
    Currency.default&.code || "USD"
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
    asset_valuations.create!(
      value: value,
      value_in_default_currency: value_in_default_currency,
      exchange_rate: exchange_rate,
      date: valuation_date || Date.current
    )
  end
end

class Account < ApplicationRecord
  belongs_to :account_type
  has_many :transactions, dependent: :destroy

  validates :name, presence: true
  validates :currency, presence: true
  validates :balance, numericality: true

  validate :currency_must_exist
  validate :currency_cannot_change, on: :update

  scope :by_currency, ->(code) { where(currency: code) }

  attribute :balance, :decimal, default: 0

  before_save :calculate_default_currency_balance

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

  def calculate_default_currency_balance
    default_curr = default_currency
    if currency == default_curr
      self.exchange_rate = 1.0
      self.balance_in_default_currency = balance
    else
      self.exchange_rate = ExchangeRateService.rate(currency, default_curr)
      self.balance_in_default_currency = (balance * exchange_rate).round(2)
    end
  end
end

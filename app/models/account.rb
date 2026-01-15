class Account < ApplicationRecord
  belongs_to :account_type
  has_many :transactions, dependent: :destroy

  validates :name, presence: true
  validates :currency, presence: true
  validates :balance, numericality: true

  validate :currency_must_exist

  scope :by_currency, ->(code) { where(currency: code) }

  attribute :balance, :decimal, default: 0

  private

  def currency_must_exist
    return if currency.blank?
    errors.add(:currency, "is not a valid currency") unless Currency.exists?(code: currency)
  end
end

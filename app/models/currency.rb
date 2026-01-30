class Currency < ApplicationRecord
  validates :code, presence: true, uniqueness: true, length: { is: 3 }
  validates :code, format: { with: /\A[A-Z]{3}\z/, message: "must be 3 uppercase letters (ISO 4217)" }

  # Ensure only one default currency exists
  before_save :clear_other_defaults, if: :default?

  def self.default
    find_by(default: true) || first
  end

  # Returns the default currency code, with ENV fallback
  def self.default_code
    default&.code || ENV.fetch("DEFAULT_CURRENCY", "USD")
  end

  private

  def clear_other_defaults
    Currency.where.not(id: id).update_all(default: false)
  end
end

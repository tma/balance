class Asset < ApplicationRecord
  belongs_to :asset_type
  has_many :asset_valuations, dependent: :destroy

  validates :name, presence: true
  validates :currency, presence: true
  validates :value, numericality: true

  validate :currency_must_exist

  scope :by_currency, ->(code) { where(currency: code) }
  scope :assets_only, -> { joins(:asset_type).where(asset_types: { is_liability: false }) }
  scope :liabilities_only, -> { joins(:asset_type).where(asset_types: { is_liability: true }) }

  attribute :value, :decimal, default: 0

  after_save :create_valuation_if_value_changed

  private

  def currency_must_exist
    return if currency.blank?
    errors.add(:currency, "is not a valid currency") unless Currency.exists?(code: currency)
  end

  def create_valuation_if_value_changed
    return unless saved_change_to_value?
    asset_valuations.create!(value: value, date: Date.current)
  end
end

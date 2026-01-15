class AssetValuation < ApplicationRecord
  belongs_to :asset

  validates :value, numericality: true
  validates :date, presence: true

  default_scope { order(date: :desc) }

  before_save :calculate_default_currency_value, unless: :value_in_default_currency?

  def default_currency
    Currency.default&.code || "USD"
  end

  private

  def calculate_default_currency_value
    default_curr = default_currency
    asset_currency = asset.currency

    if asset_currency == default_curr
      self.exchange_rate = 1.0
      self.value_in_default_currency = value
    else
      self.exchange_rate = ExchangeRateService.rate(asset_currency, default_curr)
      self.value_in_default_currency = (value * exchange_rate).round(2)
    end
  end
end

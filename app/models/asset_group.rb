class AssetGroup < ApplicationRecord
  has_many :assets, dependent: :restrict_with_error

  validates :name, presence: true

  def total_value_by_currency
    assets.group(:currency).sum(:value)
  end

  def total_assets_value_by_currency
    assets.assets_only.group(:currency).sum(:value)
  end

  def total_liabilities_value_by_currency
    assets.liabilities_only.group(:currency).sum(:value)
  end

  def net_value_by_currency
    totals = {}
    total_assets_value_by_currency.each { |currency, value| totals[currency] = value }
    total_liabilities_value_by_currency.each { |currency, value| totals[currency] = (totals[currency] || 0) - value }
    totals
  end
end

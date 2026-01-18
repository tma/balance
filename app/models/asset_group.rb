class AssetGroup < ApplicationRecord
  has_many :assets, dependent: :restrict_with_error

  validates :name, presence: true

  default_scope { order(:position, :name) }

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

  # Default currency methods
  def total_value_in_default_currency
    assets.sum(:value_in_default_currency) || 0
  end

  def total_assets_in_default_currency
    assets.assets_only.sum(:value_in_default_currency) || 0
  end

  def total_liabilities_in_default_currency
    assets.liabilities_only.sum(:value_in_default_currency) || 0
  end

  def net_value_in_default_currency
    total_assets_in_default_currency - total_liabilities_in_default_currency
  end
end

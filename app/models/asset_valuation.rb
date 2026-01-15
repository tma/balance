class AssetValuation < ApplicationRecord
  belongs_to :asset

  validates :value, numericality: true
  validates :date, presence: true

  default_scope { order(date: :desc) }
end

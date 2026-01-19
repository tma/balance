class PositionValuation < ApplicationRecord
  belongs_to :broker_position

  validates :date, presence: true
  validates :date, uniqueness: { scope: :broker_position_id }
  validates :currency, presence: true
  validates :value, numericality: true, allow_nil: true
  validates :quantity, numericality: true, allow_nil: true

  scope :on_date, ->(date) { where(date: date) }
  scope :recent, ->(limit = 30) { order(date: :desc).limit(limit) }
end

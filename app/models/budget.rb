class Budget < ApplicationRecord
  belongs_to :category

  validates :amount, numericality: { greater_than: 0 }
  validates :month, presence: true, inclusion: { in: 1..12 }
  validates :year, presence: true, numericality: { greater_than: 2000 }
  validates :category_id, uniqueness: { scope: [ :month, :year ], message: "already has a budget for this month/year" }

  scope :for_month, ->(year, month) { where(year: year, month: month) }
  scope :current_month, -> { for_month(Date.current.year, Date.current.month) }

  def spent
    Transaction.expense
               .where(category_id: category_id)
               .in_month(year, month)
               .sum(:amount)
  end

  def remaining
    amount - spent
  end

  def percentage_used
    return 0 if amount.zero?
    ((spent / amount) * 100).round(1)
  end
end

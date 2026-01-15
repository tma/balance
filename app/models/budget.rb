class Budget < ApplicationRecord
  belongs_to :category

  PERIODS = %w[monthly yearly].freeze

  validates :amount, numericality: { greater_than: 0 }
  validates :period, presence: true, inclusion: { in: PERIODS }
  validates :category_id, uniqueness: { message: "already has a budget" }

  scope :monthly, -> { where(period: "monthly") }
  scope :yearly, -> { where(period: "yearly") }

  def spent(year, month = nil)
    scope = Transaction.expense.where(category_id: category_id)

    if monthly?
      scope.in_month(year, month).sum(:amount)
    else
      scope.in_year(year).sum(:amount)
    end
  end

  def remaining(year, month = nil)
    amount - spent(year, month)
  end

  def percentage_used(year, month = nil)
    return 0 if amount.zero?
    ((spent(year, month) / amount) * 100).round(1)
  end

  def monthly?
    period == "monthly"
  end

  def yearly?
    period == "yearly"
  end

  def active_for?(date)
    start_date.nil? || date >= start_date.beginning_of_month
  end

  def period_label
    monthly? ? "per month" : "per year"
  end
end

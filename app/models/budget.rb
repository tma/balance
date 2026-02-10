class Budget < ApplicationRecord
  belongs_to :category

  PERIODS = %w[monthly yearly].freeze

  validates :amount, numericality: { greater_than: 0 }
  validates :period, presence: true, inclusion: { in: PERIODS }
  validates :category_id, uniqueness: { message: "already has a budget" }

  before_save :normalize_start_date

  scope :monthly, -> { where(period: "monthly") }
  scope :yearly, -> { where(period: "yearly") }

  def spent(year, month = nil)
    scope = Transaction.where(category_id: category_id)

    scope = if monthly?
      return 0 if month.blank?
      scope.in_month(year, month)
    else
      scope.in_year(year)
    end

    # Use signed amounts: expense transactions add to spent, income transactions
    # (refunds) subtract, so refunds reduce the budget's spent amount.
    scope.sum(Transaction.signed_amount_sql("expense"))
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

  private

  def normalize_start_date
    return if start_date.nil?

    if yearly?
      # For yearly budgets, normalize to January 1st of that year
      self.start_date = start_date.beginning_of_year
    else
      # For monthly budgets, normalize to 1st of the month
      self.start_date = start_date.beginning_of_month
    end
  end
end

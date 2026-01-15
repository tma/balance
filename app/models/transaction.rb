class Transaction < ApplicationRecord
  belongs_to :account
  belongs_to :category

  enum :transaction_type, { income: "income", expense: "expense" }

  validates :amount, numericality: { greater_than: 0 }
  validates :transaction_type, presence: true
  validates :date, presence: true

  scope :in_month, ->(year, month) { where("strftime('%Y', date) = ? AND strftime('%m', date) = ?", year.to_s, month.to_s.rjust(2, "0")) }
  scope :in_year, ->(year) { where("strftime('%Y', date) = ?", year.to_s) }
  scope :recent, ->(limit = 10) { order(date: :desc, created_at: :desc).limit(limit) }

  before_save :calculate_default_currency_amount
  after_create :update_account_balance_on_create
  after_update :update_account_balance_on_update, if: :saved_change_to_amount_or_type?
  after_destroy :update_account_balance_on_destroy

  def currency
    account&.currency
  end

  def default_currency
    Currency.default&.code || "USD"
  end

  private

  def calculate_default_currency_amount
    default_curr = default_currency
    account_currency = currency

    if account_currency == default_curr
      self.exchange_rate = 1.0
      self.amount_in_default_currency = amount
    else
      self.exchange_rate = ExchangeRateService.rate(account_currency, default_curr)
      self.amount_in_default_currency = (amount * exchange_rate).round(2)
    end
  end

  def saved_change_to_amount_or_type?
    saved_change_to_amount? || saved_change_to_transaction_type? || saved_change_to_account_id?
  end

  def update_account_balance_on_create
    adjust_account_balance(account, amount, transaction_type)
  end

  def update_account_balance_on_update
    old_amount = saved_change_to_amount? ? amount_before_last_save : amount
    old_type = saved_change_to_transaction_type? ? transaction_type_before_last_save : transaction_type
    old_account_id = saved_change_to_account_id? ? account_id_before_last_save : account_id
    old_account = Account.find_by(id: old_account_id)

    reverse_account_balance(old_account, old_amount, old_type) if old_account
    adjust_account_balance(account, amount, transaction_type)
  end

  def update_account_balance_on_destroy
    reverse_account_balance(account, amount, transaction_type)
  end

  def adjust_account_balance(acc, amt, type)
    if type == "income"
      acc.update!(balance: acc.balance + amt)
    else
      acc.update!(balance: acc.balance - amt)
    end
  end

  def reverse_account_balance(acc, amt, type)
    if type == "income"
      acc.update!(balance: acc.balance - amt)
    else
      acc.update!(balance: acc.balance + amt)
    end
  end
end

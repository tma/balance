class Transaction < ApplicationRecord
  belongs_to :account
  belongs_to :category

  enum :transaction_type, { income: "income", expense: "expense" }

  validates :amount, numericality: { greater_than: 0 }
  validates :transaction_type, presence: true
  validates :date, presence: true

  scope :in_month, ->(year, month) { where("strftime('%Y', date) = ? AND strftime('%m', date) = ?", year.to_s, month.to_s.rjust(2, "0")) }
  scope :recent, ->(limit = 10) { order(date: :desc, created_at: :desc).limit(limit) }

  after_create :update_account_balance_on_create
  after_update :update_account_balance_on_update, if: :saved_change_to_amount_or_type?
  after_destroy :update_account_balance_on_destroy

  private

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
    old_account = Account.find(old_account_id)

    reverse_account_balance(old_account, old_amount, old_type)
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

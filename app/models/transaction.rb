class Transaction < ApplicationRecord
  belongs_to :account
  belongs_to :category
  belongs_to :import, optional: true

  enum :transaction_type, { income: "income", expense: "expense" }

  validates :amount, numericality: { greater_than: 0 }
  validates :transaction_type, presence: true
  validates :date, presence: true

  scope :in_month, ->(year, month) { where("strftime('%Y', date) = ? AND strftime('%m', date) = ?", year.to_s, month.to_s.rjust(2, "0")) }
  scope :in_year, ->(year) { where("strftime('%Y', date) = ?", year.to_s) }
  scope :recent, ->(limit = 10) { order(date: :desc, created_at: :desc).limit(limit) }
  scope :search, ->(query) { where("description LIKE ?", "%#{query}%") }

  scope :needs_exchange_rate, -> { where(exchange_rate: nil).where.not(account: Account.where(currency: Currency.default&.code)) }

  # SQL expression for signed amount based on a positive direction.
  # Returns positive when transaction_type matches positive_type, negative otherwise.
  # Use for aggregating net amounts by category type (e.g., refunds reduce expenses).
  #   positive_type: "income" or "expense" — the transaction_type that counts as positive
  def self.signed_amount_sql(positive_type)
    Arel.sql(
      "CASE WHEN transactions.transaction_type = #{connection.quote(positive_type)} " \
      "THEN transactions.amount_in_default_currency " \
      "ELSE -transactions.amount_in_default_currency END"
    )
  end

  # SQL expression for signed amount matching transaction_type against the joined
  # category's category_type. Returns positive when they match (normal flow),
  # negative when they differ (refunds/corrections).
  # Requires the query to join :category.
  def self.signed_amount_by_category_type_sql
    Arel.sql(
      "CASE WHEN transactions.transaction_type = categories.category_type " \
      "THEN transactions.amount_in_default_currency " \
      "ELSE -transactions.amount_in_default_currency END"
    )
  end

  before_save :calculate_default_currency_amount
  before_save :calculate_duplicate_hash
  after_create :update_account_balance_on_create
  after_update :update_account_balance_on_update, if: :saved_change_to_amount_or_type?
  after_destroy :update_account_balance_on_destroy

  def currency
    account&.currency
  end

  def default_currency
    Currency.default_code
  end

  private

  def calculate_default_currency_amount
    default_curr = default_currency
    account_currency = currency

    if account_currency == default_curr
      self.exchange_rate = 1.0
      self.amount_in_default_currency = amount
    else
      # Use historical exchange rate for the transaction date
      rate = ExchangeRateService.rate(account_currency, default_curr, date: date)
      if rate.nil?
        # Skip conversion if rate unavailable - will be retried later
        Rails.logger.warn "Exchange rate unavailable for #{account_currency}->#{default_curr}, skipping conversion for transaction"
        return
      end
      self.exchange_rate = rate
      self.amount_in_default_currency = (amount * exchange_rate).round(2)
    end
  end

  def calculate_duplicate_hash
    self.duplicate_hash = DuplicateDetectionService.hash_for(date, amount, description)
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
      acc.increment!(:balance, amt)
    else
      acc.decrement!(:balance, amt)
    end
  end

  def reverse_account_balance(acc, amt, type)
    if type == "income"
      acc.decrement!(:balance, amt)
    else
      acc.increment!(:balance, amt)
    end
  end
end

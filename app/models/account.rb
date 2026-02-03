class Account < ApplicationRecord
  include AccountCoverage

  DEFAULT_IGNORE_PATTERNS = <<~PATTERNS.freeze
    Total
    Subtotal
    Balance
    Credit Limit
    Payment Due
    Statement Period
  PATTERNS

  belongs_to :account_type
  has_many :transactions, dependent: :destroy
  has_many :imports, dependent: :destroy

  validates :name, presence: true
  validates :currency, presence: true
  validates :balance, numericality: true

  validate :currency_must_exist
  validate :currency_cannot_change, on: :update

  scope :by_currency, ->(code) { where(currency: code) }
  scope :needs_exchange_rate, -> { where(exchange_rate: nil).where.not(currency: Currency.default&.code) }
  scope :active, -> { where(archived: false) }
  scope :archived, -> { where(archived: true) }

  attribute :balance, :decimal, default: 0

  before_save :calculate_default_currency_balance

  # Returns array of ignore patterns for import filtering
  # Uses custom patterns if set, otherwise falls back to defaults
  def ignore_patterns_list
    patterns = import_ignore_patterns.presence || DEFAULT_IGNORE_PATTERNS
    patterns.lines.map(&:strip).reject(&:blank?)
  end

  # Check if a description matches any ignore pattern (case-sensitive)
  def should_ignore_for_import?(description)
    desc = description.to_s
    ignore_patterns_list.any? { |pattern| desc.include?(pattern) }
  end

  def default_currency
    Currency.default_code
  end

  # Returns cached CSV column mapping as a hash, or nil if not set
  def cached_csv_mapping
    return nil if csv_column_mapping.blank?
    JSON.parse(csv_column_mapping, symbolize_names: true)
  rescue JSON::ParserError
    nil
  end

  # Stores a CSV column mapping for future imports
  def cache_csv_mapping!(mapping)
    update!(csv_column_mapping: mapping.to_json)
  end

  # Check if account has pending or processing imports
  def has_pending_imports?
    imports.where(status: %w[pending processing]).exists?
  end

  def archive!
    if has_pending_imports?
      errors.add(:base, "Cannot archive account with pending imports")
      raise ActiveRecord::RecordInvalid, self
    end
    update!(archived: true)
  end

  def unarchive!
    update!(archived: false)
  end

  private

  def currency_must_exist
    return if currency.blank?
    errors.add(:currency, "is not a valid currency") unless Currency.exists?(code: currency)
  end

  def currency_cannot_change
    if currency_changed? && currency_was.present?
      errors.add(:currency, "cannot be changed after creation")
    end
  end

  def calculate_default_currency_balance
    default_curr = default_currency
    if currency == default_curr
      self.exchange_rate = 1.0
      self.balance_in_default_currency = balance
    else
      rate = ExchangeRateService.rate(currency, default_curr, date: Date.current)
      if rate.nil?
        Rails.logger.warn "Exchange rate unavailable for #{currency}->#{default_curr}, skipping conversion for account"
        return
      end
      self.exchange_rate = rate
      self.balance_in_default_currency = (balance * exchange_rate).round(2)
    end
  end
end

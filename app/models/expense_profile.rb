class ExpenseProfile < ApplicationRecord
  belongs_to :category

  CADENCES = {
    "monthly" => 12,
    "quarterly" => 4,
    "semiannual" => 2,
    "annual" => 1
  }.freeze
  ESSENTIALITIES = %w[essential discretionary excluded].freeze
  RECURRENCE_CONFIDENCES = %w[high medium low].freeze

  enum :source, { human: "human", machine: "machine" }, prefix: true
  enum :status,
       { suggested: "suggested", confirmed: "confirmed", dismissed: "dismissed", inactive: "inactive" },
       prefix: true

  serialize :review_flags, coder: JSON, type: Array
  attribute :review_flags, default: -> { [] }

  validates :merchant_pattern, presence: true,
                               uniqueness: { scope: :category_id, case_sensitive: false }
  validates :essentiality, inclusion: { in: ESSENTIALITIES }, allow_nil: true
  validates :cadence, inclusion: { in: CADENCES.keys }, allow_nil: true
  validates :detected_cadence, inclusion: { in: CADENCES.keys }, allow_nil: true
  validates :recurrence_confidence, inclusion: { in: RECURRENCE_CONFIDENCES }, allow_nil: true
  validates :confirmed_amount, numericality: { greater_than: 0 }, allow_nil: true
  validate :category_must_be_expense
  validate :confirmed_profile_is_classified
  validate :recurring_confirmation_has_amount

  scope :review_queue, -> {
    suggested = where(status: "suggested")
      .where("recurrence_confidence IN ('high', 'medium') OR review_flags LIKE ?", "%material%")
    suggested.or(where(status: "confirmed").where("COALESCE(review_flags, '[]') != '[]'"))
  }

  def self.best_match(profiles, description)
    profiles.select { |profile| profile.matches_description?(description) }
      .max_by { |profile| [ profile.merchant_pattern.length, -profile.id.to_i ] }
  end

  def matches_description?(description)
    description.to_s.match?(/\b#{Regexp.escape(merchant_pattern)}\b/i)
  end

  def recurring?
    cadence.present?
  end

  def fixed_commitment?
    status_confirmed? && essentiality == "essential" && !category.essentiality_excluded? &&
      recurring? && confirmed_amount.present?
  end

  def annualized_amount(amount: confirmed_amount, cadence_value: cadence)
    return 0.to_d if amount.blank? || cadence_value.blank?

    amount.to_d * CADENCES.fetch(cadence_value)
  end

  def projected_annual_impact
    if detected_cadence.present?
      annualized_amount(amount: median_amount, cadence_value: detected_cadence)
    else
      trailing_annual_amount.to_d
    end
  end

  def confirm!(essentiality:, cadence: nil, confirmed_amount: nil)
    update!(
      essentiality: essentiality,
      cadence: cadence.presence,
      confirmed_amount: confirmed_amount.presence,
      status: "confirmed",
      confirmed_at: Time.current,
      review_flags: []
    )
  end

  private

  def category_must_be_expense
    errors.add(:category, "must be an expense category") unless category&.expense?
  end

  def confirmed_profile_is_classified
    return unless status_confirmed? && essentiality.blank?

    errors.add(:essentiality, "must be selected for a confirmed profile")
  end

  def recurring_confirmation_has_amount
    return unless status_confirmed? && cadence.present? && confirmed_amount.blank?

    errors.add(:confirmed_amount, "is required for a confirmed recurring profile")
  end
end

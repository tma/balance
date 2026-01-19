class Category < ApplicationRecord
  has_many :transactions, dependent: :restrict_with_error
  has_many :budgets, dependent: :destroy

  enum :category_type, { income: "income", expense: "expense" }

  validates :name, presence: true, uniqueness: { scope: :category_type }
  validates :category_type, presence: true

  # Returns array of match patterns for categorization hints
  def match_patterns_list
    return [] if match_patterns.blank?

    match_patterns.lines.map(&:strip).reject(&:blank?)
  end

  # Returns true if this category has match patterns defined
  def has_match_patterns?
    match_patterns_list.any?
  end
end

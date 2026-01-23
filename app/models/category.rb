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

  # Check if a description matches any of this category's patterns (case-insensitive)
  def matches_description?(description)
    return false unless has_match_patterns?

    desc_lower = description.to_s.downcase
    match_patterns_list.any? { |pattern| desc_lower.include?(pattern.downcase) }
  end

  # Find a category that matches the description using pattern matching
  # @param description [String] Transaction description
  # @param type [String] "income" or "expense"
  # @return [Category, nil] Matching category or nil
  def self.find_by_pattern(description, type)
    where(category_type: type).find { |cat| cat.matches_description?(description) }
  end
end

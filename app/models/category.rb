class Category < ApplicationRecord
  has_many :transactions, dependent: :restrict_with_error
  has_many :budgets, dependent: :destroy

  enum :category_type, { income: "income", expense: "expense" }

  validates :name, presence: true, uniqueness: { scope: :category_type }
  validates :category_type, presence: true

  after_save :schedule_embedding_update, if: :embedding_attributes_changed?

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

  # Text used for generating the embedding vector
  # Combines name, type, and match patterns for rich semantic representation
  def embedding_text
    parts = [ name, "(#{category_type})" ]
    parts << "- #{match_patterns_list.join(', ')}" if has_match_patterns?
    parts.join(" ")
  end

  # Get embedding as array of floats (unpacked from binary)
  # @return [Array<Float>, nil] The embedding vector or nil if not set
  def embedding_vector
    return nil if embedding.blank?
    embedding.unpack("f*")
  end

  # Set embedding from array of floats (packed to binary)
  # @param vector [Array<Float>, nil] The embedding vector
  def embedding_vector=(vector)
    self.embedding = vector&.pack("f*")
  end

  private

  def embedding_attributes_changed?
    saved_change_to_name? || saved_change_to_match_patterns?
  end

  def schedule_embedding_update
    CategoryEmbeddingJob.perform_later(id)
  end
end

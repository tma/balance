class Category < ApplicationRecord
  has_many :transactions, dependent: :restrict_with_error
  has_many :budgets, dependent: :destroy
  has_many :category_patterns, dependent: :destroy

  enum :category_type, { income: "income", expense: "expense" }

  validates :name, presence: true, uniqueness: { scope: :category_type }
  validates :category_type, presence: true

  after_save :schedule_embedding_update, if: :embedding_attributes_changed?

  # Returns array of match patterns for categorization hints
  # Reads from CategoryPattern table (human-defined patterns)
  def match_patterns_list
    if persisted?
      category_patterns.human.pluck(:pattern)
    else
      []
    end
  end

  # Returns true if this category has match patterns defined
  def has_match_patterns?
    match_patterns_list.any?
  end

  # Check if a description matches any of this category's patterns (case-insensitive)
  def matches_description?(description)
    return false unless has_match_patterns?

    category_patterns.human.any? { |p| p.matches?(description) }
  end

  # Find a category that matches the description using pattern matching
  # Uses CategoryPattern table with human priority over machine patterns
  # @param description [String] Transaction description
  # @param type [String] "income" or "expense"
  # @return [Category, nil] Matching category or nil
  def self.find_by_pattern(description, type)
    category_ids = where(category_type: type).pluck(:id)

    # Human patterns first (priority)
    human_match = CategoryPattern
      .where(category_id: category_ids, source: "human")
      .find { |p| p.matches?(description) }

    if human_match
      human_match.increment_match_count!
      return human_match.category
    end

    # Machine patterns second — highest confidence wins, match_count as tiebreaker
    machine_match = CategoryPattern
      .where(category_id: category_ids, source: "machine")
      .order(confidence: :desc, match_count: :desc)
      .find { |p| p.matches?(description) }

    if machine_match
      machine_match.increment_match_count!
      return machine_match.category
    end

    nil
  end

  # Text used for generating the embedding vector
  # Combines name, type, and match patterns for rich semantic representation
  def embedding_text
    parts = [ name, "(#{category_type})" ]
    patterns = persisted? ? category_patterns.pluck(:pattern) : []
    parts << "- #{patterns.join(', ')}" if patterns.any?
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
    saved_change_to_name?
  end

  def schedule_embedding_update
    CategoryEmbeddingJob.perform_later(id)
  end
end

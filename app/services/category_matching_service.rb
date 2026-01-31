# 3-phase transaction categorization service using pattern matching, embeddings, and LLM
#
# Phase 1: Rule-based pattern matching (free, instant)
# Phase 2: Embedding similarity search (fast, ~15-50ms per transaction)
# Phase 3: LLM categorization with reduced candidate set (slower, but more accurate)
#
# IMPORTANT: Requires the embedding model (nomic-embed-text) to be available.
# If the model is not available, ALL categorization is skipped.
class CategoryMatchingService
  TOP_K_CANDIDATES = 3

  attr_reader :transactions, :on_progress

  # Initialize the service with transactions to categorize
  # @param transactions [Array<Hash>] Array of transaction hashes with :description, :transaction_type
  # @param on_progress [Proc, nil] Optional callback for progress updates (current, total, message)
  def initialize(transactions, on_progress: nil)
    @transactions = transactions
    @on_progress = on_progress
    @expense_categories = nil
    @income_categories = nil
  end

  # Categorize all transactions using 3-phase approach
  # Sets :category_id and :category_name on each transaction hash
  # @return [void]
  def categorize
    return if transactions.empty?

    unless OllamaService.embedding_model_available?
      Rails.logger.warn "CategoryMatchingService: Embedding model not available, skipping all categorization"
      return
    end

    load_categories

    transactions.each_with_index do |txn, index|
      categorize_transaction(txn)
      report_progress(index + 1, transactions.size, "Categorizing transactions")
    end
  end

  private

  def load_categories
    @expense_categories = Category.expense.to_a
    @income_categories = Category.income.to_a
  end

  def categories_for_type(type)
    type == "income" ? @income_categories : @expense_categories
  end

  def categorize_transaction(txn)
    type = txn[:transaction_type]
    description = txn[:description]

    # Phase 1: Rule-based pattern matching
    category = Category.find_by_pattern(description, type)
    if category
      assign_category(txn, category, phase: 1)
      return
    end

    # Phase 2: Embedding similarity
    result = find_by_embedding(description, type)
    if result[:category]
      assign_category(txn, result[:category], phase: 2)
      return
    end

    # Phase 3: LLM with top candidates
    if result[:candidates]&.any?
      category = llm_categorize_single(txn, result[:candidates])
      assign_category(txn, category, phase: 3) if category
    end
  end

  def assign_category(txn, category, phase: nil)
    txn[:category_id] = category.id
    txn[:category_name] = category.name
    Rails.logger.debug { "CategoryMatchingService: '#{txn[:description]}' -> '#{category.name}' (phase #{phase})" }
  end

  # Phase 2: Find category by embedding similarity
  # @return [Hash] { category: Category or nil, candidates: Array<Category> or nil }
  def find_by_embedding(description, type)
    candidates = embedding_candidates(description, type)
    return { category: nil, candidates: nil } if candidates.empty?

    top_match = candidates.first
    if top_match[:similarity] >= confidence_threshold
      { category: top_match[:category], confidence: top_match[:similarity], candidates: nil }
    else
      { category: nil, confidence: top_match[:similarity], candidates: candidates.map { |c| c[:category] } }
    end
  end

  def embedding_candidates(description, type)
    query_vector = OllamaService.embed(description)
    categories = categories_for_type(type)

    categories
      .select { |cat| cat.embedding.present? }
      .map { |cat| { category: cat, similarity: cosine_similarity(cat.embedding_vector, query_vector) } }
      .sort_by { |c| -c[:similarity] }
      .first(TOP_K_CANDIDATES)
  rescue OllamaService::Error => e
    Rails.logger.warn "CategoryMatchingService: Embedding failed for '#{description}': #{e.message}"
    []
  end

  def cosine_similarity(a, b)
    return 0.0 if a.nil? || b.nil? || a.empty? || b.empty?

    # Warn if dimensions don't match (likely model mismatch)
    if a.size != b.size
      Rails.logger.warn "CategoryMatchingService: Embedding dimension mismatch (#{a.size} vs #{b.size}). " \
                        "Run 'rails categories:compute_embeddings' to recompute with current model."
      return 0.0
    end

    dot = a.zip(b).sum { |x, y| x * y }
    mag_a = Math.sqrt(a.sum { |x| x**2 })
    mag_b = Math.sqrt(b.sum { |x| x**2 })
    return 0.0 if mag_a.zero? || mag_b.zero?

    dot / (mag_a * mag_b)
  end

  # Phase 3: LLM categorization with reduced candidate set
  def llm_categorize_single(txn, candidates)
    return nil if candidates.empty?

    prompt = build_llm_prompt(txn, candidates)
    response = OllamaService.generate_json(prompt)
    category_name = parse_llm_response(response)

    find_category_by_name(category_name, txn[:transaction_type])
  rescue OllamaService::Error => e
    Rails.logger.warn "CategoryMatchingService: LLM categorization failed: #{e.message}"
    nil
  end

  def build_llm_prompt(txn, candidates)
    candidate_names = candidates.map(&:name)
    hints = candidates.select(&:has_match_patterns?).map do |cat|
      "- #{cat.name}: #{cat.match_patterns_list.join(', ')}"
    end

    <<~PROMPT
      Categorize this transaction into ONE of the given categories.

      TRANSACTION: [#{txn[:transaction_type].upcase}] #{txn[:description]} (#{txn[:amount]})

      CATEGORIES: #{candidate_names.join(", ")}
      #{hints.any? ? "\nHINTS:\n#{hints.join("\n")}" : ""}

      Return JSON with the exact category name:
      {"category": "category name"}
    PROMPT
  end

  def parse_llm_response(response)
    case response
    when Hash
      response["category"] || response["name"] || response.values.first
    when String
      response.strip
    else
      nil
    end
  end

  def find_category_by_name(name, type)
    return nil if name.blank?

    name_str = name.to_s.strip
    categories = categories_for_type(type)

    # Exact match
    category = categories.find { |c| c.name == name_str }
    return category if category

    # Case-insensitive match
    categories.find { |c| c.name.downcase == name_str.downcase }
  end

  def confidence_threshold
    Rails.application.config.ollama.embedding_confidence_threshold
  end

  def report_progress(current, total, message)
    on_progress&.call(current, total, message: message)
  end
end

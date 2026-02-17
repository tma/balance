# 3-phase transaction categorization service using pattern matching, embeddings, and LLM
#
# Phase 1: Rule-based pattern matching via CategoryPattern (free, instant)
# Phase 2: Embedding similarity search — transaction-level nearest neighbor, then category-level (fast, ~15-50ms)
# Phase 3: LLM categorization with few-shot examples from transaction history (slower, but more accurate)
#
# IMPORTANT: Requires the embedding model to be available.
# If the model is not available, ALL categorization is skipped.
class CategoryMatchingService
  TOP_K_CANDIDATES = 3
  TOP_K_TRANSACTION_NEIGHBORS = 5
  FEW_SHOT_LIMIT = 5

  attr_reader :transactions, :on_progress

  # Initialize the service with transactions to categorize
  # @param transactions [Array<Hash>] Array of transaction hashes with :description, :transaction_type
  # @param on_progress [Proc, nil] Optional callback for progress updates (current, total, message)
  def initialize(transactions, on_progress: nil)
    @transactions = transactions
    @on_progress = on_progress
    @expense_categories = nil
    @income_categories = nil
    @transaction_embeddings_cache = {}
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
    preload_transaction_embeddings

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

  # Preload transaction embeddings for nearest-neighbor search
  # Caches by type to avoid repeated queries during batch categorization
  # Limited to the most recent 1000 per type to keep memory and CPU bounded
  MAX_EMBEDDING_TRANSACTIONS = 1000

  def preload_transaction_embeddings
    %w[income expense].each do |type|
      @transaction_embeddings_cache[type] = Transaction.joins(:category)
        .where(categories: { category_type: type })
        .where.not(embedding: nil)
        .order(date: :desc)
        .limit(MAX_EMBEDDING_TRANSACTIONS)
        .select(:id, :category_id, :embedding, :description)
        .to_a
    end
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

    # Phase 2: Embedding similarity (transaction-level, then category-level)
    result = find_by_embedding(description, type)
    if result[:category]
      assign_category(txn, result[:category], phase: 2)
      return
    end

    # Phase 3: LLM with top candidates and few-shot examples
    if result[:candidates]&.any?
      category = llm_categorize_single(txn, result[:candidates])
      assign_category(txn, category, phase: 3) if category
    end
  end

  def assign_category(txn, category, phase: nil)
    txn[:category_id] = category.id
    txn[:category_name] = category.name
    txn[:matched_phase] = phase
    Rails.logger.debug { "CategoryMatchingService: '#{txn[:description]}' -> '#{category.name}' (phase #{phase})" }
  end

  # Phase 2: Find category by embedding similarity
  # First searches transaction embeddings (fine-grained, user history),
  # then falls back to category embeddings (coarse, always available).
  # @return [Hash] { category: Category or nil, candidates: Array<Category> or nil }
  def find_by_embedding(description, type)
    query_vector = OllamaService.embed(description)

    # Search transaction embeddings first (fine-grained, user history)
    txn_candidates = nearest_transaction_neighbors(query_vector, type, k: TOP_K_TRANSACTION_NEIGHBORS)

    if txn_candidates.any? && txn_candidates.first[:similarity] >= transaction_confidence_threshold
      # Strong match from history — return directly
      return { category: txn_candidates.first[:category], candidates: nil }
    end

    # Fall back to category embeddings (coarse, always available)
    cat_candidates = nearest_category_neighbors(query_vector, type, k: TOP_K_CANDIDATES)

    if cat_candidates.any? && cat_candidates.first[:similarity] >= category_confidence_threshold
      return { category: cat_candidates.first[:category], candidates: nil }
    end

    # Low confidence — pass all candidates to Phase 3
    all_candidates = (txn_candidates.map { |c| c[:category] } +
                      cat_candidates.map { |c| c[:category] }).uniq
    { category: nil, candidates: all_candidates }
  rescue OllamaService::Error => e
    Rails.logger.warn "CategoryMatchingService: Embedding failed for '#{description}': #{e.message}"
    { category: nil, candidates: nil }
  end

  # Find nearest transaction neighbors using preloaded embeddings
  def nearest_transaction_neighbors(query_vector, type, k:)
    cached = @transaction_embeddings_cache[type]
    return [] if cached.nil? || cached.empty?

    cached
      .map { |t| { category: t.category, similarity: cosine_similarity(t.embedding_vector, query_vector), description: t.description } }
      .sort_by { |c| -c[:similarity] }
      .first(k)
  end

  # Find nearest category neighbors (original Phase 2 behavior)
  def nearest_category_neighbors(query_vector, type, k:)
    categories = categories_for_type(type)

    categories
      .select { |cat| cat.embedding.present? }
      .map { |cat| { category: cat, similarity: cosine_similarity(cat.embedding_vector, query_vector) } }
      .sort_by { |c| -c[:similarity] }
      .first(k)
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
    # Retrieve similar historical transactions as few-shot examples
    examples = retrieve_few_shot_examples(txn[:description], txn[:transaction_type], limit: FEW_SHOT_LIMIT)

    candidate_names = candidates.map(&:name)

    examples_text = if examples.any?
      "SIMILAR TRANSACTIONS YOU'VE CATEGORIZED BEFORE:\n" +
      examples.map { |e| "- \"#{e[:description]}\" -> #{e[:category_name]}" }.join("\n") + "\n\n"
    else
      ""
    end

    <<~PROMPT
      Categorize this transaction into ONE of the given categories.

      #{examples_text}TRANSACTION: [#{txn[:transaction_type].upcase}] #{txn[:description]} (#{txn[:amount]})

      CATEGORIES: #{candidate_names.join(", ")}

      Return JSON with the exact category name:
      {"category": "category name"}
    PROMPT
  end

  # Retrieve similar historical transactions as few-shot examples for LLM prompts
  def retrieve_few_shot_examples(description, type, limit:)
    cached = @transaction_embeddings_cache[type]
    return [] if cached.nil? || cached.empty?

    query_vector = OllamaService.embed(description)

    cached
      .filter_map { |t|
        sim = cosine_similarity(t.embedding_vector, query_vector)
        { description: t.description, category_name: t.category.name, similarity: sim } if sim > 0
      }
      .sort_by { |e| -e[:similarity] }
      .first(limit)
  rescue OllamaService::Error
    []
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

  # Transaction-level embedding confidence threshold
  # Slightly higher than category-level since transaction embeddings are more specific
  def transaction_confidence_threshold
    category_confidence_threshold
  end

  # Category-level embedding confidence threshold (original behavior)
  def category_confidence_threshold
    Rails.application.config.ollama.embedding_confidence_threshold
  end

  def report_progress(current, total, message)
    on_progress&.call(current, total, message: message)
  end
end

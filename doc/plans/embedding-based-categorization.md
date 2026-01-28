# Hybrid Embedding-Based Transaction Categorization

## Overview

Optimize transaction categorization during import by using vector embeddings to pre-filter categories before calling the LLM. This reduces LLM calls by 70-80% and shrinks prompt size from 30 categories to 3.

## Problem

Currently, when categorizing transactions during import (`TransactionExtractorService`):

1. **All 30 categories** are sent in every LLM prompt (~500 tokens)
2. **Every uncategorized transaction** requires an LLM call
3. **No semantic understanding** - relies on exact pattern matching or full LLM

This is inefficient for a fixed, small category set.

## Proposed Solution

A 3-phase hybrid approach:

```
Transaction Description
        ↓
  Phase 1: Rule-based check (match_patterns) ← existing, FREE
        ↓ (no match)
  Phase 2: Embed description → cosine similarity vs category embeddings (~15-50ms)
        ↓
  Confidence > 85%? → Return top match (skip LLM)
        ↓ (low confidence)
  Phase 3: LLM with TOP 3 candidates only (~100 tokens, ~500ms)
        ↓
  Return category
```

## Research Findings

### Embedding vs LLM Classification

| Aspect | Embedding Approach | Direct LLM |
|--------|-------------------|------------|
| Speed | ~15-50ms (local) | ~500-2000ms |
| Cost | Near-zero after setup | Per-token costs |
| Accuracy | ~62-68% zero-shot | ~75-85% with good prompts |
| Nuance | Limited (semantic only) | Handles context, edge cases |

**Conclusion**: Hybrid approach gets best of both - speed for clear matches, accuracy for ambiguous cases.

### Vector Storage: Binary vs JSON

| Operation | Binary (`pack`/`unpack`) | JSON |
|-----------|--------------------------|------|
| Storage size (768 floats) | 3 KB | ~15-20 KB |
| Deserialize time | ~0.01-0.05ms | ~0.5-2ms |
| 30 categories total | ~0.3-1.5ms | ~15-60ms |

**Conclusion**: Binary is ~10-50x faster and ~5x more compact. Use `pack("f*")` / `unpack("f*")`.

### SQLite Vector Options

For ~30 categories, no extension needed:
- `sqlite-vec` exists but adds complexity
- Pure Ruby cosine similarity is fast enough (~0.5ms for all 30)
- Store embeddings as binary column, compute similarity in Ruby

### Ollama Embedding Models

| Model | Dimensions | Size | Use Case |
|-------|-----------|------|----------|
| `nomic-embed-text` | 768 | 274MB | Best balance (recommended) |
| `all-minilm` | 384 | smaller | Faster, less accurate |
| `mxbai-embed-large` | 1024 | larger | Higher precision |

**Conclusion**: Use `nomic-embed-text` - good quality, reasonable size.

## Design Decisions

### 1. Embedding Input Text (Option C)

Use category name + type + existing match_patterns:

```ruby
def embedding_text
  parts = [name, "(#{category_type})"]
  parts << "- #{match_patterns_list.join(', ')}" if has_match_patterns?
  parts.join(" ")
end
```

Examples:
- `"Groceries (expense) - food, supermarket, Whole Foods, Costco"`
- `"Transportation (expense) - uber, lyft, taxi"`
- `"Salary (income)"` (no patterns, just name + type)

**Rationale**: Leverages existing `match_patterns` data without schema changes for descriptions.

### 2. Embedding Updates (Option 3 - Background Job)

Embeddings recalculated via background job when category attributes change:

```ruby
after_save :schedule_embedding_update, if: :embedding_attributes_changed?

def embedding_attributes_changed?
  saved_change_to_name? || saved_change_to_match_patterns?
end

def schedule_embedding_update
  CategoryEmbeddingJob.perform_later(id)
end
```

**Rationale**: Non-blocking saves, categories change rarely anyway.

### 3. Confidence Threshold

- **Threshold**: 0.85 (configurable via ENV)
- **Top-K candidates**: 3 (for LLM fallback)

If top embedding match ≥ 0.85, use it directly. Otherwise, pass top 3 to LLM for decision.

## Final Implementation Decisions

1. **Architecture**: Use dedicated `CategoryMatchingService` for 3-phase categorization logic
2. **Scope**: CSV imports only (via `TransactionImportJob`); PDF imports unchanged
3. **Model unavailable behavior**: When embedding model is not available, log warning and **skip ALL categorization** (transactions imported without categories)
4. **Testing**: Full test coverage for all new code

## Implementation Plan

### Files to Create

| File | Description |
|------|-------------|
| `db/migrate/xxx_add_embedding_to_categories.rb` | Add `embedding` binary column |
| `app/services/category_matching_service.rb` | 3-phase categorization logic |
| `app/jobs/category_embedding_job.rb` | Background job for embedding updates |
| `lib/tasks/categories.rake` | `rails categories:compute_embeddings` task |
| `test/services/category_matching_service_test.rb` | Tests for the service |
| `test/jobs/category_embedding_job_test.rb` | Tests for the job |

### Files to Modify

| File | Changes |
|------|---------|
| `app/models/category.rb` | Add `embedding_text`, `embedding_vector` accessors, callback for job |
| `app/services/ollama_service.rb` | Add `embed(text)` and `embedding_model_available?` methods |
| `app/jobs/transaction_import_job.rb` | Replace `categorize_transactions` with `CategoryMatchingService` |
| `config/initializers/ollama.rb` | Add embedding model config |
| `test/models/category_test.rb` | Tests for embedding methods |
| `test/services/ollama_service_test.rb` | Tests for embed method |

### Migration

```ruby
class AddEmbeddingToCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :categories, :embedding, :binary
  end
end
```

### OllamaService.embed

```ruby
EMBEDDING_MODEL = "nomic-embed-text"

def self.embed(text)
  raise UnavailableError, "Ollama is not available" unless available?

  response = HTTParty.post(
    "#{config.host}/api/embeddings",
    body: { model: EMBEDDING_MODEL, prompt: text }.to_json,
    headers: { "Content-Type" => "application/json" },
    timeout: 30
  )

  if response.success?
    response.parsed_response["embedding"]
  else
    raise Error, "Ollama embedding error: #{response.code}"
  end
end
```

### Category Model Additions

```ruby
# Text used for embedding calculation
def embedding_text
  parts = [name, "(#{category_type})"]
  parts << "- #{match_patterns_list.join(', ')}" if has_match_patterns?
  parts.join(" ")
end

# Get embedding as array of floats
def embedding_vector
  return nil if embedding.blank?
  embedding.unpack("f*")
end

# Set embedding from array of floats
def embedding_vector=(vector)
  self.embedding = vector&.pack("f*")
end

# Callbacks for auto-update
after_save :schedule_embedding_update, if: :embedding_attributes_changed?

private

def embedding_attributes_changed?
  saved_change_to_name? || saved_change_to_match_patterns?
end

def schedule_embedding_update
  CategoryEmbeddingJob.perform_later(id)
end

# Class methods
class << self
  CONFIDENCE_THRESHOLD = 0.85
  TOP_K_CANDIDATES = 3

  def find_by_embedding(description, type)
    candidates = embedding_candidates(description, type, TOP_K_CANDIDATES)
    return nil if candidates.empty?

    top_match = candidates.first
    if top_match[:similarity] >= CONFIDENCE_THRESHOLD
      { category: top_match[:category], confidence: top_match[:similarity], candidates: nil }
    else
      { category: nil, confidence: top_match[:similarity], candidates: candidates.map { |c| c[:category] } }
    end
  end

  def embedding_candidates(description, type, limit)
    query_vector = OllamaService.embed(description)
    
    where(category_type: type)
      .where.not(embedding: nil)
      .map { |cat| { category: cat, similarity: cosine_similarity(cat.embedding_vector, query_vector) } }
      .sort_by { |c| -c[:similarity] }
      .first(limit)
  end

  def cosine_similarity(a, b)
    return 0.0 if a.nil? || b.nil?
    dot = a.zip(b).sum { |x, y| x * y }
    mag_a = Math.sqrt(a.sum { |x| x**2 })
    mag_b = Math.sqrt(b.sum { |x| x**2 })
    return 0.0 if mag_a.zero? || mag_b.zero?
    dot / (mag_a * mag_b)
  end
end
```

### CategoryMatchingService

New service to encapsulate the 3-phase categorization logic:

```ruby
class CategoryMatchingService
  CONFIDENCE_THRESHOLD = 0.85
  TOP_K_CANDIDATES = 3

  def initialize(transactions)
    @transactions = transactions
  end

  def categorize
    return skip_categorization unless embedding_model_available?
    
    @transactions.each do |txn|
      categorize_transaction(txn)
    end
  end

  private

  def embedding_model_available?
    OllamaService.embedding_model_available?
  end

  def skip_categorization
    Rails.logger.warn "Embedding model not available, skipping categorization"
    # Transactions remain without categories
  end

  def categorize_transaction(txn)
    # Phase 1: Rule-based pattern matching
    category = Category.find_by_pattern(txn[:description], txn[:transaction_type])
    return assign_category(txn, category) if category

    # Phase 2: Embedding similarity
    result = find_by_embedding(txn[:description], txn[:transaction_type])
    return assign_category(txn, result[:category]) if result[:category]

    # Phase 3: LLM with top candidates
    category = llm_categorize(txn, result[:candidates])
    assign_category(txn, category)
  end
end
```

### TransactionImportJob Changes

Replace inline `categorize_transactions` method with `CategoryMatchingService`:

```ruby
def categorize_transactions(transactions, account, import: nil, ...)
  return if transactions.empty?
  
  CategoryMatchingService.new(transactions).categorize do |progress|
    import&.update_progress!(...)
  end
end
```

### Rake Task

```ruby
namespace :categories do
  desc "Compute embeddings for all categories"
  task compute_embeddings: :environment do
    unless OllamaService.available?
      puts "Error: Ollama is not available"
      exit 1
    end

    categories = Category.all
    puts "Computing embeddings for #{categories.count} categories..."

    categories.each do |category|
      print "  #{category.name}... "
      vector = OllamaService.embed(category.embedding_text)
      category.update_column(:embedding, vector.pack("f*"))
      puts "✓"
    end

    puts "Done!"
  end
end
```

## Configuration

Add to `config/initializers/ollama.rb`:

```ruby
config.embedding_model = ENV.fetch("OLLAMA_EMBEDDING_MODEL", "nomic-embed-text")
config.embedding_confidence_threshold = ENV.fetch("OLLAMA_EMBEDDING_CONFIDENCE", 0.85).to_f
```

## Rollout Steps

1. `ollama pull nomic-embed-text` - download embedding model
2. `rails db:migrate` - add embedding column
3. `rails categories:compute_embeddings` - populate initial embeddings
4. Deploy - graceful fallback if embeddings missing

## Expected Performance

| Metric | Before | After |
|--------|--------|-------|
| LLM calls needed | 100% of uncategorized | ~20-30% |
| Tokens per LLM call | ~500 | ~100 |
| Avg latency per txn | ~100-200ms | ~20-50ms |
| Prompt size | 30 categories | 3 categories |

## Embedding Model Requirement

**IMPORTANT**: The embedding model (`nomic-embed-text`) is REQUIRED for categorization.

When the embedding model is not available:
- Log a warning: "Embedding model not available, skipping categorization"
- Skip ALL categorization (pattern matching, embedding, LLM)
- Transactions are imported without categories
- Users can manually categorize or re-import after pulling the model

## Future Enhancements

1. **Description-to-category cache**: Cache successful categorizations for instant repeated lookups
2. **User feedback loop**: Learn from user corrections to improve matching
3. **Category descriptions**: Add optional `description` field for richer embeddings
4. **Batch embedding**: Embed multiple transaction descriptions in one call (if Ollama supports)

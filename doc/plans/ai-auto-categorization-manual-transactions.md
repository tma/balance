# Smart Transaction Categorization

## Overview

Upgrade the existing 3-phase categorization pipeline to learn from every user-confirmed categorization. Replace the manually-maintained `match_patterns` text field with a structured `CategoryPattern` table that separates human-entered patterns from machine-learned ones. Add transaction-level embeddings and few-shot retrieval to make Phases 2 and 3 dramatically more accurate over time. Expose real-time category suggestions on the manual transaction form.

## Problem

The current system has three limitations:

1. **Phase 1 (pattern matching) requires manual curation.** The user must enter patterns like "Whole Foods" into a text field on each category. These patterns are never auto-populated from transaction history.

2. **Phase 2 (embedding similarity) compares against category-level embeddings only.** There are ~30 category embeddings, derived from abstract text like "Groceries (expense) - food, supermarket." This is a poor semantic match for real bank descriptions like "WHOLEFDS MKT #1234 SEATTLE WA."

3. **Phase 3 (LLM fallback) has no context about the user's history.** The LLM receives only the description and 3 candidate category names — no examples of how the user has categorized similar transactions before.

Additionally, categorization only runs during imports. Manually created transactions require the user to pick from a dropdown.

## Proposed Solution

### Learning Pipeline

Every user-confirmed categorization (via import acceptance or manual entry) feeds back into all three phases:

```
User confirms "WHOLEFDS MKT #1234" → Groceries
        |
        ├── Phase 1: Extract "WHOLEFDS MKT" → store as machine CategoryPattern
        |             (future exact matches skip embedding/LLM entirely)
        |
        ├── Phase 2: Store embedding of "WHOLEFDS MKT #1234" with category_id
        |             (future similar descriptions match via nearest-neighbor)
        |
        └── Phase 3: Available as few-shot example for LLM prompts
                      (future ambiguous cases get user-specific context)
```

### Two Jobs (Hybrid Approach)

**`TransactionEmbeddingJob`** — lightweight, per-transaction:
- Triggered `after_commit` when a transaction is created or its category changes
- Embeds the single transaction description (~50ms)
- Stores the embedding vector on the transaction
- Very fast, safe to run on every save

**`PatternExtractionJob`** — heavier, batched on schedule:
- Runs nightly via Solid Queue
- Also enqueued after an import completes
- Finds recently-embedded transactions not yet covered by a `CategoryPattern`
- Groups by category, extracts merchant names via LLM in batches
- Creates/updates `CategoryPattern` records with `source: "machine"`
- Updates match counts on existing patterns
- Idempotent — safe to run multiple times

### Bootstrapping & Self-Healing

The hourly `PatternExtractionJob` is the primary self-healing mechanism. Every run it:
1. Backfills any missing transaction embeddings (catches Ollama downtime)
2. Extracts patterns for any uncovered transactions

This means the system naturally catches up without manual intervention. A bootstrap rake task exists for convenience when you want an immediate full rebuild rather than waiting for the next hourly run.

Daily `CategorizationMaintenanceJob` handles data quality: pruning stale patterns, detecting re-categorization drift, and resolving conflicts. A manual `EmbeddingModelMigrationJob` handles the rare case of switching embedding models.

### Real-Time Suggestions

A Stimulus-driven async category suggestion on the manual transaction form. When the user types a description, debounce and call the upgraded `CategoryMatchingService`, then pre-select the suggested category.

## Design Decisions

### 1. CategoryPattern Table (Human vs Machine Separation)

Replace the `match_patterns` text field on Category with a `category_patterns` table:

```ruby
CategoryPattern
- id: integer
- category_id: references
- pattern: string              # the text pattern (e.g., "WHOLEFDS MKT")
- source: string               # "human" or "machine"
- match_count: integer          # how many transactions matched (default: 0)
- confidence: decimal           # for machine patterns (0.0-1.0)
- created_at: datetime
- updated_at: datetime
- unique index on [pattern, source]
```

**Why a separate table over a second text column:**
- Per-pattern metadata (match count, confidence, creation date)
- Individual deletion of machine patterns without parsing text blobs
- Clean regeneration: `CategoryPattern.where(source: "machine").delete_all`
- Admin UI can sort by frequency, show match counts
- Unique index prevents duplicate patterns

**Migration of existing data:**
- Split existing `match_patterns` text into rows with `source: "human"`
- Keep `match_patterns` column temporarily for rollback safety, remove later
- Existing `Category.find_by_pattern` and `matches_description?` methods updated to query the table

### 2. Human Patterns Always Take Priority

When a description matches both a human pattern on category A and a machine pattern on category B, the human pattern wins. Implementation: check all human patterns first across all categories, then check machine patterns.

### 3. Admin UI: Machine Patterns Visible but Read-Only

On the category edit page:

```
Match Patterns (manual)                    ← editable textarea
┌──────────────────────────────────┐
│ Whole Foods                      │
│ Trader Joe                       │
└──────────────────────────────────┘

Learned Patterns                           ← read-only, with match counts
┌──────────────────────────────────────────────────────┐
│ WHOLEFDS MKT          47 matches    ✕               │
│ TRADER JOES           32 matches    ✕               │
│ COSTCO WHSE           28 matches    ✕               │
│ SPROUTS FARMERS       12 matches    ✕               │
└──────────────────────────────────────────────────────┘
                                      [Clear & Regenerate]
```

- "✕" removes an individual machine pattern
- "Clear & Regenerate" deletes all machine patterns for this category and enqueues `PatternExtractionJob`
- Human patterns remain in an editable textarea (converted to `CategoryPattern` rows with `source: "human"` on save)

### 4. Transaction Embeddings

Add an `embedding` binary column to the `transactions` table. Same binary packing as categories (`pack("f*")` / `unpack("f*")`).

Phase 2 then searches against both:
- **Category embeddings** (~30 vectors) — coarse semantic match, good for truly novel descriptions
- **Transaction embeddings** (hundreds/thousands) — fine-grained match against real descriptions the user has seen before

The transaction embedding lookup uses nearest-neighbor: find the k most similar previously-categorized transactions, vote by category. If the top match is above a confidence threshold, return it directly. Otherwise, pass the top candidates to Phase 3.

**Performance note:** With a few thousand transactions, brute-force cosine similarity in Ruby is still fast (~5-10ms). No vector database needed for this scale.

### 5. Few-Shot Retrieval for Phase 3

When Phase 3 (LLM) is invoked, retrieve 3-5 most similar previously-categorized transactions using the same embedding similarity from Phase 2. Include them in the prompt:

```
Here are similar transactions you've categorized before:
- "WHOLEFDS MKT #987" → Groceries
- "TRADER JOES #234" → Groceries
- "SPROUTS FARMERS #12" → Groceries

CATEGORIES: Groceries, Dining, Shopping

Now categorize: "NATURAL GROCERS #456"
Return JSON: {"category": "category name"}
```

This gives the LLM user-specific categorization context, pushing accuracy from ~80% to ~90%+.

### 6. Merchant Name Extraction

`PatternExtractionJob` needs to extract the stable merchant identifier from variable bank descriptions. Examples:

| Bank Description | Merchant Pattern |
|-----------------|-----------------|
| `WHOLEFDS MKT #1234 SEATTLE WA` | `WHOLEFDS MKT` |
| `SHELL OIL 57442 PORTLAND OR` | `SHELL OIL` |
| `AMZN MKTP US*2K4X7B1C3` | `AMZN MKTP` |

This is itself a good LLM task. The prompt:

```
Extract the merchant name from these transaction descriptions.
Strip store numbers, locations, dates, and reference codes.

1. "WHOLEFDS MKT #1234 SEATTLE WA"
2. "SHELL OIL 57442 PORTLAND OR"
3. "AMZN MKTP US*2K4X7B1C3"

Return JSON: ["WHOLEFDS MKT", "SHELL OIL", "AMZN MKTP"]
```

**Minimum threshold:** Only create a machine pattern if the extracted merchant name appears in 2+ transactions for the same category. This prevents one-off purchases from polluting the pattern list.

### 7. Debounce + Graceful Degradation for Manual Suggestions

- **Debounce**: 300ms after user stops typing
- **Minimum length**: 3 characters before triggering a request
- **Cancel**: Abort in-flight requests when new keystrokes arrive
- **Ollama unavailable**: Return `{ category_id: null }`, dropdown works normally
- **User override**: If user manually selects a category before suggestion returns, ignore the suggestion

### 8. Category Embedding Updates

When a `CategoryPattern` is created/updated/deleted, the parent category's embedding should be recomputed (via the existing `CategoryEmbeddingJob`) since `embedding_text` incorporates patterns. The `Category#embedding_text` method should be updated to pull from `CategoryPattern` records instead of the `match_patterns` text field.

## Data Model Changes

### New Table: `category_patterns`

```ruby
class CreateCategoryPatterns < ActiveRecord::Migration[8.1]
  def change
    create_table :category_patterns do |t|
      t.references :category, null: false, foreign_key: true
      t.string :pattern, null: false
      t.string :source, null: false, default: "human"  # "human" or "machine"
      t.integer :match_count, default: 0
      t.decimal :confidence                              # 0.0-1.0, machine only
      t.timestamps
    end

    add_index :category_patterns, [:pattern, :source], unique: true
    add_index :category_patterns, [:category_id, :source]
  end
end
```

### Modify: `transactions` — add embedding column

```ruby
class AddEmbeddingToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :embedding, :binary
  end
end
```

### Data Migration: `match_patterns` → `category_patterns`

```ruby
class MigrateMatchPatternsToCategoryPatterns < ActiveRecord::Migration[8.1]
  def up
    Category.where.not(match_patterns: [nil, ""]).find_each do |category|
      category.match_patterns.lines.map(&:strip).reject(&:blank?).each do |pattern|
        CategoryPattern.create!(
          category: category,
          pattern: pattern,
          source: "human",
          match_count: 0
        )
      end
    end
  end

  def down
    # Reverse: aggregate human patterns back into text field
    Category.find_each do |category|
      patterns = CategoryPattern.where(category: category, source: "human").pluck(:pattern)
      category.update_column(:match_patterns, patterns.join("\n")) if patterns.any?
    end
    CategoryPattern.delete_all
  end
end
```

## New Model: CategoryPattern

```ruby
class CategoryPattern < ApplicationRecord
  belongs_to :category

  SOURCES = %w[human machine].freeze

  validates :pattern, presence: true
  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :pattern, uniqueness: { scope: :source }

  scope :human, -> { where(source: "human") }
  scope :machine, -> { where(source: "machine") }
  scope :by_match_count, -> { order(match_count: :desc) }

  after_commit :schedule_category_embedding_update

  def human?
    source == "human"
  end

  def machine?
    source == "machine"
  end

  def increment_match_count!
    increment!(:match_count)
  end

  private

  def schedule_category_embedding_update
    CategoryEmbeddingJob.perform_later(category_id)
  end
end
```

## Updated Phase 1: Pattern Matching via CategoryPattern

```ruby
# In CategoryMatchingService or Category model

def find_by_pattern(description, type)
  desc_lower = description.to_s.downcase
  category_ids = Category.where(category_type: type).pluck(:id)

  # Human patterns first (priority)
  human_match = CategoryPattern
    .where(category_id: category_ids, source: "human")
    .find { |p| desc_lower.include?(p.pattern.downcase) }

  if human_match
    human_match.increment_match_count!
    return human_match.category
  end

  # Machine patterns second
  machine_match = CategoryPattern
    .where(category_id: category_ids, source: "machine")
    .find { |p| desc_lower.include?(p.pattern.downcase) }

  if machine_match
    machine_match.increment_match_count!
    return machine_match.category
  end

  nil
end
```

## Updated Phase 2: Transaction-Level Nearest Neighbor

```ruby
def find_by_embedding(description, type)
  query_vector = OllamaService.embed(description)

  # Search transaction embeddings (fine-grained, user history)
  txn_candidates = nearest_transaction_neighbors(query_vector, type, k: 5)

  if txn_candidates.any? && txn_candidates.first[:similarity] >= transaction_confidence_threshold
    # Strong match from history — return directly
    return { category: txn_candidates.first[:category], candidates: nil }
  end

  # Fall back to category embeddings (coarse, always available)
  cat_candidates = nearest_category_neighbors(query_vector, type, k: 3)

  if cat_candidates.any? && cat_candidates.first[:similarity] >= category_confidence_threshold
    return { category: cat_candidates.first[:category], candidates: nil }
  end

  # Low confidence — pass all candidates to Phase 3
  all_candidates = (txn_candidates.map { |c| c[:category] } +
                    cat_candidates.map { |c| c[:category] }).uniq
  { category: nil, candidates: all_candidates }
end

def nearest_transaction_neighbors(query_vector, type, k:)
  # Load embedded transactions for the given type
  # In practice, preload and cache these for the duration of a categorization batch
  Transaction.joins(:category)
    .where(categories: { category_type: type })
    .where.not(embedding: nil)
    .select(:id, :category_id, :embedding, :description)
    .map { |t| { category: t.category, similarity: cosine_similarity(t.embedding_vector, query_vector), description: t.description } }
    .sort_by { |c| -c[:similarity] }
    .first(k)
end
```

## Updated Phase 3: Few-Shot Retrieval

```ruby
def build_llm_prompt(txn, candidates)
  # Retrieve similar historical transactions as few-shot examples
  examples = retrieve_few_shot_examples(txn[:description], txn[:transaction_type], limit: 5)

  candidate_names = candidates.map(&:name)

  examples_text = if examples.any?
    "SIMILAR TRANSACTIONS YOU'VE CATEGORIZED BEFORE:\n" +
    examples.map { |e| "- \"#{e[:description]}\" → #{e[:category_name]}" }.join("\n") + "\n\n"
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

def retrieve_few_shot_examples(description, type, limit:)
  query_vector = OllamaService.embed(description)

  Transaction.joins(:category)
    .where(categories: { category_type: type })
    .where.not(embedding: nil)
    .select(:description, :embedding, "categories.name as category_name")
    .map { |t| { description: t.description, category_name: t.category_name, similarity: cosine_similarity(t.embedding_vector, query_vector) } }
    .sort_by { |e| -e[:similarity] }
    .first(limit)
end
```

## Jobs

### TransactionEmbeddingJob (per-transaction, immediate)

```ruby
class TransactionEmbeddingJob < ApplicationJob
  queue_as :default

  retry_on OllamaService::UnavailableError, wait: :polynomially_longer, attempts: 3
  retry_on OllamaService::TimeoutError, wait: 30.seconds, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(transaction_id)
    transaction = Transaction.find(transaction_id)

    unless OllamaService.embedding_model_available?
      Rails.logger.warn "TransactionEmbeddingJob: Embedding model not available, skipping"
      return
    end

    return if transaction.embedding.present?  # Already embedded

    vector = OllamaService.embed(transaction.description)
    transaction.update_column(:embedding, vector.pack("f*"))
  end
end
```

**Trigger on Transaction model:**
```ruby
after_commit :schedule_embedding, on: [:create, :update], if: :needs_embedding?

def needs_embedding?
  saved_change_to_description? || saved_change_to_category_id? || embedding.blank?
end

def schedule_embedding
  TransactionEmbeddingJob.perform_later(id)
end
```

### PatternExtractionJob (batched, hourly + post-import)

```ruby
class PatternExtractionJob < ApplicationJob
  queue_as :default

  MINIMUM_OCCURRENCES = 2  # Merchant must appear 2+ times to become a pattern

  def perform(category_id: nil, full_rebuild: false)
    # Self-healing: backfill any missing transaction embeddings first
    backfill_missing_embeddings

    if full_rebuild
      CategoryPattern.machine.delete_all
    elsif category_id
      CategoryPattern.machine.where(category_id: category_id).delete_all
    end

    scope = category_id ? Transaction.where(category_id: category_id) : Transaction.all
    process_transactions(scope)
  end

  private

  # Enqueue embedding jobs for transactions that are missing embeddings.
  # This catches cases where Ollama was unavailable when the transaction
  # was created, or where TransactionEmbeddingJob failed and exhausted retries.
  def backfill_missing_embeddings
    unembedded = Transaction.where(embedding: nil).where.not(description: [nil, ""])
    count = unembedded.count
    return if count.zero?

    Rails.logger.info "PatternExtractionJob: backfilling #{count} missing embeddings"
    unembedded.find_each do |txn|
      TransactionEmbeddingJob.perform_later(txn.id)
    end
  end

  def process_transactions(scope)
    # Group transactions by category, extract merchant names
    scope.joins(:category)
         .where.not(description: nil)
         .group_by(&:category_id)
         .each do |cat_id, transactions|
      descriptions = transactions.map(&:description).uniq
      uncovered = descriptions.reject { |d| covered_by_pattern?(d, cat_id) }
      next if uncovered.empty?

      merchants = extract_merchant_names(uncovered)
      create_patterns(cat_id, merchants, descriptions)
    end
  end

  def extract_merchant_names(descriptions)
    # Batch LLM call to extract merchant identifiers
    prompt = <<~PROMPT
      Extract the merchant/company name from each transaction description.
      Strip store numbers, locations, dates, and reference codes.
      Return ONLY the stable merchant identifier.

      #{descriptions.each_with_index.map { |d, i| "#{i + 1}. \"#{d}\"" }.join("\n")}

      Return JSON array of merchant names in the same order:
      ["MERCHANT1", "MERCHANT2", ...]
    PROMPT

    response = OllamaService.generate_json(prompt)
    Array(response).map(&:to_s).map(&:strip)
  rescue OllamaService::Error => e
    Rails.logger.warn "PatternExtractionJob: LLM extraction failed: #{e.message}"
    []
  end

  def create_patterns(category_id, merchants, descriptions)
    # Count occurrences of each merchant across descriptions
    merchant_counts = merchants.tally

    merchant_counts.each do |merchant, count|
      next if merchant.blank? || count < MINIMUM_OCCURRENCES

      # Skip if a human pattern already covers this
      next if CategoryPattern.human.where(category_id: category_id)
                              .any? { |p| merchant.downcase.include?(p.pattern.downcase) }

      CategoryPattern.find_or_create_by!(
        pattern: merchant,
        source: "machine"
      ) do |p|
        p.category_id = category_id
        p.confidence = (count.to_f / descriptions.size).round(2)
        p.match_count = count
      end
    end
  end

  def covered_by_pattern?(description, category_id)
    CategoryPattern.where(category_id: category_id)
                   .any? { |p| description.downcase.include?(p.pattern.downcase) }
  end
end
```

**Scheduled in `config/recurring.yml`:**

```yaml
hourly_pattern_extraction:
  class: PatternExtractionJob
  queue: default
  schedule: every hour
```

**Triggered after import:**

```ruby
# In TransactionImportJob, after successful import
PatternExtractionJob.perform_later
```

### Bootstrap Rake Task

Convenience wrapper for initial setup or manual re-bootstrapping. The hourly `PatternExtractionJob` will naturally catch up on its own (it backfills missing embeddings and extracts patterns for uncovered transactions every run), so this task is not strictly necessary — but it's useful for triggering an immediate full rebuild rather than waiting for the next scheduled run.

```ruby
namespace :categorization do
  desc "Bootstrap categorization from existing transaction history"
  task bootstrap: :environment do
    unless OllamaService.available?
      puts "Error: Ollama is not available"
      exit 1
    end

    puts "Enqueuing full rebuild (embeddings + patterns)..."
    puts "The hourly PatternExtractionJob handles this automatically,"
    puts "but this triggers it immediately with a full rebuild."

    # Step 1: Embed all transactions without embeddings
    transactions = Transaction.where(embedding: nil)
    puts "Enqueuing embedding for #{transactions.count} transactions..."
    transactions.find_each do |txn|
      TransactionEmbeddingJob.perform_later(txn.id)
    end

    # Step 2: Extract patterns (full rebuild)
    puts "Enqueuing pattern extraction (full rebuild)..."
    PatternExtractionJob.perform_later(full_rebuild: true)

    puts "Jobs enqueued. Monitor with: rails solid_queue:monitor"
  end
end
```

## Maintenance & Self-Healing Jobs

### CategorizationMaintenanceJob (daily scheduled)

Handles data quality tasks that don't require LLM calls — pure database cleanup.

```ruby
class CategorizationMaintenanceJob < ApplicationJob
  queue_as :default

  STALE_PATTERN_AGE = 30.days
  DRIFT_THRESHOLD = 0.6  # 60%+ of matched transactions re-categorized = stale

  def perform
    prune_stale_patterns
    prune_orphaned_patterns
    detect_recategorization_drift
    resolve_conflicting_patterns
  end

  private

  # Remove machine patterns that were extracted but never matched anything
  # after 30 days — likely noise from the LLM extraction
  def prune_stale_patterns
    stale = CategoryPattern.machine
                           .where(match_count: 0)
                           .where("created_at < ?", STALE_PATTERN_AGE.ago)

    count = stale.count
    stale.delete_all
    Rails.logger.info "CategorizationMaintenance: pruned #{count} stale patterns" if count > 0
  end

  # Defensive: remove patterns whose category was deleted
  # Shouldn't happen with foreign key constraints, but belts and suspenders
  def prune_orphaned_patterns
    orphaned = CategoryPattern.left_joins(:category).where(categories: { id: nil })
    count = orphaned.count
    orphaned.delete_all
    Rails.logger.info "CategorizationMaintenance: pruned #{count} orphaned patterns" if count > 0
  end

  # Detect machine patterns where the majority of matching transactions
  # have been re-categorized by the user to a different category.
  # This means the pattern is no longer accurate.
  def detect_recategorization_drift
    CategoryPattern.machine.where("match_count > 0").find_each do |pattern|
      matching_txns = Transaction.where("LOWER(description) LIKE ?", "%#{pattern.pattern.downcase}%")
      next if matching_txns.empty?

      # Count how many still belong to the pattern's category vs. others
      same_category = matching_txns.where(category_id: pattern.category_id).count
      total = matching_txns.count
      ratio = same_category.to_f / total

      if ratio < (1.0 - DRIFT_THRESHOLD)
        Rails.logger.info "CategorizationMaintenance: removing drifted pattern " \
                          "\"#{pattern.pattern}\" (#{same_category}/#{total} still match category)"
        pattern.destroy
      end
    end
  end

  # If the same merchant pattern exists under multiple categories,
  # keep the one with the higher match count, remove the others.
  # Human patterns are never removed — only machine duplicates.
  def resolve_conflicting_patterns
    # Find machine patterns that share a pattern string with another record
    # (different category, same or different source)
    CategoryPattern.machine
                   .group(:pattern)
                   .having("COUNT(DISTINCT category_id) > 1")
                   .pluck(:pattern)
                   .each do |pattern_text|

      duplicates = CategoryPattern.machine.where(pattern: pattern_text).order(match_count: :desc)
      winner = duplicates.first
      losers = duplicates.offset(1)

      count = losers.count
      losers.delete_all
      Rails.logger.info "CategorizationMaintenance: resolved conflict for \"#{pattern_text}\", " \
                        "kept category #{winner.category_id}, removed #{count} duplicates" if count > 0
    end
  end
end
```

**Scheduled in `config/recurring.yml`:**

```yaml
daily_categorization_maintenance:
  class: CategorizationMaintenanceJob
  queue: default
  schedule: every day at 3am UTC
```

### EmbeddingModelMigrationJob (manual, rake-triggered)

When the embedding model changes (e.g., upgrading from `nomic-embed-text` to a newer model), all stored embeddings are invalidated because vector dimensions and semantics change. This job clears everything and rebuilds from scratch.

```ruby
class EmbeddingModelMigrationJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "EmbeddingModelMigration: clearing all embeddings..."

    # Clear transaction embeddings
    txn_count = Transaction.where.not(embedding: nil).count
    Transaction.where.not(embedding: nil).update_all(embedding: nil)
    Rails.logger.info "EmbeddingModelMigration: cleared #{txn_count} transaction embeddings"

    # Clear category embeddings
    cat_count = Category.where.not(embedding: nil).count
    Category.where.not(embedding: nil).update_all(embedding: nil)
    Rails.logger.info "EmbeddingModelMigration: cleared #{cat_count} category embeddings"

    # Clear machine patterns (they were derived from old embeddings/LLM context)
    pattern_count = CategoryPattern.machine.count
    CategoryPattern.machine.delete_all
    Rails.logger.info "EmbeddingModelMigration: cleared #{pattern_count} machine patterns"

    # Re-enqueue embedding jobs for everything
    Transaction.find_each { |t| TransactionEmbeddingJob.perform_later(t.id) }
    Category.find_each { |c| CategoryEmbeddingJob.perform_later(c.id) }

    Rails.logger.info "EmbeddingModelMigration: enqueued re-embedding for " \
                      "#{txn_count} transactions and #{cat_count} categories"
  end
end
```

**Rake task:**

```ruby
namespace :categorization do
  desc "Re-embed everything after changing the embedding model"
  task migrate_embeddings: :environment do
    unless OllamaService.available?
      puts "Error: Ollama is not available"
      exit 1
    end

    puts "This will clear ALL embeddings and machine patterns, then rebuild."
    puts "Embedding jobs will be enqueued in the background."
    EmbeddingModelMigrationJob.perform_later
    puts "EmbeddingModelMigrationJob enqueued. Monitor with: rails solid_queue:monitor"
  end
end
```

## Real-Time Suggestion Endpoint

### Route

```ruby
resources :transactions do
  collection do
    post :suggest_category
  end
end
```

### Controller Action

```ruby
def suggest_category
  description = params[:description].to_s.strip
  transaction_type = params[:transaction_type].to_s.strip

  if description.length < 3
    render json: { category_id: nil }
    return
  end

  txn = {
    description: description,
    transaction_type: transaction_type,
    amount: 0,
    category_id: nil,
    category_name: nil
  }

  service = CategoryMatchingService.new([txn])
  service.categorize

  render json: {
    category_id: txn[:category_id],
    category_name: txn[:category_name]
  }
rescue StandardError => e
  Rails.logger.warn "Category suggestion failed: #{e.message}"
  render json: { category_id: nil }
end
```

### Stimulus Controller

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["description", "category", "badge"]
  static values = { url: String, userSelected: Boolean }

  connect() {
    this.userSelectedValue = false
    this.timeout = null
    this.abortController = null
  }

  suggest() {
    this.userSelectedValue = false
    clearTimeout(this.timeout)
    this.abortController?.abort()

    const description = this.descriptionTarget.value.trim()
    if (description.length < 3) return

    this.timeout = setTimeout(() => this.fetchSuggestion(description), 300)
  }

  manualSelect() {
    this.userSelectedValue = true
    this.hideBadge()
  }

  async fetchSuggestion(description) {
    this.abortController = new AbortController()
    const type = this.element.querySelector('[name*="transaction_type"]:checked')?.value || "expense"

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify({ description, transaction_type: type }),
        signal: this.abortController.signal
      })

      const data = await response.json()
      if (data.category_id && !this.userSelectedValue) {
        this.categoryTarget.value = data.category_id
        this.showBadge()
      }
    } catch (e) {
      if (e.name !== "AbortError") console.warn("Category suggestion failed:", e)
    }
  }

  showBadge() {
    if (this.hasBadgeTarget) this.badgeTarget.classList.remove("hidden")
  }

  hideBadge() {
    if (this.hasBadgeTarget) this.badgeTarget.classList.add("hidden")
  }
}
```

## Admin UI Changes

### Category Form (`_form.html.erb`)

The human patterns textarea stays as-is (but now saves to `CategoryPattern` rows).

Below it, add a read-only section for machine-learned patterns:

```erb
<% if category.persisted? %>
  <% machine_patterns = category.category_patterns.machine.by_match_count %>
  <% if machine_patterns.any? %>
    <div class="mb-4">
      <label class="<%= ui_label_class %>">Learned Patterns</label>
      <div class="<%= ui_card_class %> p-3 space-y-1">
        <% machine_patterns.each do |pattern| %>
          <div class="flex items-center justify-between text-sm">
            <code class="font-mono"><%= pattern.pattern %></code>
            <div class="flex items-center space-x-3">
              <span class="<%= ui_text_muted_class %>"><%= pattern.match_count %> matches</span>
              <%= button_to "✕", admin_category_pattern_path(category, pattern),
                  method: :delete, class: "text-gray-400 hover:text-red-500",
                  data: { turbo_confirm: "Remove this pattern?" } %>
            </div>
          </div>
        <% end %>
      </div>
      <div class="mt-2">
        <%= button_to "Clear & Regenerate",
            regenerate_admin_category_patterns_path(category),
            method: :post,
            class: ui_btn_secondary_class + " text-xs",
            data: { turbo_confirm: "Delete all learned patterns and regenerate from transaction history?" } %>
      </div>
    </div>
  <% end %>
<% end %>
```

## Files to Create

| File | Description |
|------|-------------|
| `db/migrate/xxx_create_category_patterns.rb` | CategoryPattern table |
| `db/migrate/xxx_add_embedding_to_transactions.rb` | Embedding column on transactions |
| `db/migrate/xxx_migrate_match_patterns_to_category_patterns.rb` | Data migration |
| `app/models/category_pattern.rb` | CategoryPattern model |
| `app/jobs/transaction_embedding_job.rb` | Per-transaction embedding job |
| `app/jobs/pattern_extraction_job.rb` | Batched merchant extraction job (hourly + post-import) |
| `app/jobs/categorization_maintenance_job.rb` | Daily data quality maintenance job |
| `app/jobs/embedding_model_migration_job.rb` | Manual job for embedding model changes |
| `app/javascript/controllers/category_suggest_controller.js` | Stimulus controller |
| `lib/tasks/categorization.rake` | Bootstrap + model migration rake tasks |
| `test/models/category_pattern_test.rb` | Model tests |
| `test/jobs/transaction_embedding_job_test.rb` | Job tests |
| `test/jobs/pattern_extraction_job_test.rb` | Job tests |
| `test/jobs/categorization_maintenance_job_test.rb` | Maintenance job tests |
| `test/jobs/embedding_model_migration_job_test.rb` | Migration job tests |
| `test/controllers/transactions_controller_suggest_test.rb` | Endpoint tests |
| `lib/categorization_benchmark.rb` | Benchmark runner class with synthetic dataset and accuracy thresholds |
| `test/migrations/migrate_match_patterns_test.rb` | Data migration edge case tests |

## Files to Modify

| File | Changes |
|------|---------|
| `app/models/category.rb` | Add `has_many :category_patterns`, update `embedding_text` to use CategoryPattern, update `find_by_pattern` |
| `app/models/transaction.rb` | Add `embedding_vector`/`embedding_vector=` accessors, `after_commit` to enqueue embedding job |
| `app/services/category_matching_service.rb` | Add transaction-level nearest-neighbor (Phase 2), few-shot retrieval (Phase 3), use CategoryPattern for Phase 1 |
| `app/controllers/transactions_controller.rb` | Add `suggest_category` action |
| `app/views/admin/categories/_form.html.erb` | Add learned patterns section |
| `app/views/transactions/_form.html.erb` | Wire up Stimulus controller |
| `config/routes.rb` | Add routes for suggestion endpoint, pattern management |
| `config/recurring.yml` | Add hourly `PatternExtractionJob` and daily `CategorizationMaintenanceJob` schedules |
| `app/jobs/transaction_import_job.rb` | Enqueue `PatternExtractionJob` after import completes |
| `db/seeds.rb` | Dual-schema category seeding (detect `CategoryPattern` table, write to both old and new) |

## Performance Considerations

- **Transaction embedding lookup**: With ~2,000 transactions, brute-force cosine similarity in Ruby takes ~5-10ms. No vector DB needed at this scale.
- **Preloading**: During batch categorization (imports), preload all transaction embeddings for the relevant type once, not per-transaction.
- **Embedding column size**: 768 floats × 4 bytes = ~3KB per transaction. At 2,000 transactions = ~6MB total. Negligible.
- **Pattern extraction batching**: LLM calls for merchant extraction are batched (10-20 descriptions per prompt). A backfill of 2,000 transactions requires ~100-200 LLM calls spread over a background job.

## Graceful Degradation

| Component | When Ollama unavailable |
|-----------|------------------------|
| Phase 1 (patterns) | Works normally — no Ollama dependency |
| Phase 2 (embeddings) | Falls back to category-level embeddings only (existing behavior) |
| Phase 3 (LLM) | Skipped — returns best embedding match or null |
| Transaction embedding job | Logs warning, retries later |
| Pattern extraction job | Logs warning, retries later |
| Manual suggestion endpoint | Returns `{ category_id: null }` |

## Testing Strategy

### Unit Tests (`rails test`)

Standard test suite — fast, fully mocked, runs in CI:

- **CategoryPattern model**: Validations, scopes, match_count increment, human/machine separation
- **Phase 1 update**: Human priority over machine, match_count tracking
- **Phase 2 update**: Transaction-level nearest-neighbor with mock embeddings
- **Phase 3 update**: Few-shot example retrieval and prompt construction
- **TransactionEmbeddingJob**: Embeds description, skips if already embedded, handles Ollama unavailability
- **PatternExtractionJob**: Extracts merchants, creates patterns with threshold, respects human pattern priority, idempotent, backfills missing embeddings
- **CategorizationMaintenanceJob**: Prunes stale patterns, detects drift, resolves conflicts, handles empty database gracefully
- **EmbeddingModelMigrationJob**: Clears all embeddings and patterns, enqueues re-embedding jobs
- **Suggest endpoint**: Returns valid JSON, handles short descriptions, handles Ollama unavailability

### Data Migration Tests (`rails test`)

Verify the `match_patterns` → `category_patterns` data migration handles all edge cases. The migration logic is extracted into a testable method so it can be exercised without running actual migrations:

- **Multiline patterns**: `"whole foods\ntrader joe\nsafeway"` → 3 `CategoryPattern` rows with `source: "human"`
- **Empty/nil patterns**: Categories with `match_patterns: nil` or `""` produce no rows
- **Whitespace handling**: Leading/trailing whitespace stripped, blank lines skipped
- **Duplicate patterns**: Same pattern text on different categories creates separate rows (unique index is `[pattern, source]`, not `[pattern]` alone)
- **Rollback (`down`)**: Aggregates human `CategoryPattern` rows back into `match_patterns` text, one per line
- **Idempotency**: Running the migration logic twice doesn't create duplicate rows

### Pipeline Accuracy Benchmark (`rake categorization:benchmark`)

**NOT part of `rails test`** — requires real Ollama, run on demand to validate pipeline accuracy.

**Synthetic dataset** (~80-100 transactions based on seeded categories):

| Category | Phase 1 Targets (pattern match) | Phase 2/3 Targets (needs embeddings/LLM) |
|----------|--------------------------------|------------------------------------------|
| Groceries | `WHOLEFDS MKT #1234 SEATTLE WA`, `TRADER JOES #567`, `SAFEWAY STORE #890`, `KROGER #4521`, `WALMART SUPERCENTER #123` | `SPROUTS FARMERS MKT #45`, `NATURAL GROCERS #789`, `H-E-B GROCERY #321`, `PUBLIX SUPER MARKETS INC`, `PIGGLY WIGGLY #12` |
| Dining | `GRUBHUB*THAI KITCHEN`, `DOORDASH*PIZZAHUT` | `MCDONALDS F1234`, `STARBUCKS STORE #56789`, `CHIPOTLE ONLINE ORDER`, `SQ *LOCAL BISTRO`, `PANERA BREAD #4567`, `TST* SUSHI PLACE` |
| Transportation | `UBER TRIP HELP.UBER.COM`, `LYFT *RIDE 12345` | `METRO TRANSIT AUTH`, `PARKING METER SF`, `TOLL CHARGE I-95`, `CITIBIKE MEMBERSHIP` |
| Gas | `SHELL OIL 57442634829`, `CHEVRON STN 1234`, `EXXON` | `MARATHON PETRO 5678`, `BP #8765432 PORTLAND`, `ARCO AMPM #4321` |
| Subscriptions | `NETFLIX.COM`, `SPOTIFY USA`, `HULU *MONTHLY`, `AMAZON PRIME MEMBERSHIP` | `CHATGPT SUBSCRIPTION`, `APPLE.COM/BILL`, `YOUTUBE PREMIUM` |
| Healthcare | `CVS/PHARMACY #1234`, `WALGREENS #5678` | `KAISER PERMANENTE`, `QUEST DIAGNOSTICS`, `DR SMITH MEDICAL GRP` |
| Utilities | — | `PGE ELECTRIC BILL`, `AT&T WIRELESS`, `COMCAST CABLE`, `CITY OF SF WATER`, `VERIZON WIRELESS PAY` |
| Entertainment | — | `AMC THEATRES #1234`, `TICKETMASTER`, `REGAL CINEMAS`, `STUBHUB INC`, `MUSEUM OF MODERN ART` |
| Travel | — | `UNITED AIRLINES`, `MARRIOTT HOTEL`, `AIRBNB *HMXYZ123`, `EXPEDIA INC`, `DELTA AIR LINES`, `HILTON HOTELS` |
| Insurance | `GEICO AUTO PAY`, `STATE FARM INS` | `ALLSTATE PREMIUM`, `PROGRESSIVE INS` |

**Execution flow:**

1. Verify Ollama is available (exit with error if not)
2. Ensure seeded categories exist with embeddings
3. For each test transaction:
   a. Run Phase 1 (pattern matching) only — record hit/miss
   b. Run Phase 2 (embedding similarity) only — record hit/miss
   c. Run full pipeline (all 3 phases) — record final category
4. Compute accuracy per phase and per category
5. Report results and compare against thresholds

**Accuracy thresholds:**

| Metric | Threshold | Rationale |
|--------|-----------|-----------|
| Phase 1 (pattern match) | >= 95% | Known merchant substrings should almost always match |
| Phase 2 (embedding similarity) | >= 80% | Semantically similar descriptions should cluster correctly |
| Phase 3 (LLM fallback) | >= 75% | Ambiguous descriptions are genuinely hard |
| Overall pipeline | >= 85% | Combined accuracy across all phases |

**Output format:**

```
== Categorization Pipeline Benchmark ==
Ollama: available (nomic-embed-text, llama3.2)
Categories: 21 expense, 8 income (29 total)
Test transactions: 87

Phase 1 (Pattern Matching):
  Groceries:       5/5  (100%)
  Dining:          2/2  (100%)
  ...
  Phase 1 total:  18/19 ( 95%)  PASS (threshold: 95%)

Phase 2 (Embedding Similarity):
  Groceries:       4/5  ( 80%)
  ...
  Phase 2 total:  30/37 ( 81%)  PASS (threshold: 80%)

Phase 3 (LLM Fallback):
  ...
  Phase 3 total:   6/7  ( 86%)  PASS (threshold: 75%)

Overall Pipeline:
  Total:          78/87 ( 90%)  PASS (threshold: 85%)

Summary: 4/4 metrics passed
```

**Implementation:**

The benchmark logic lives in `lib/categorization_benchmark.rb` (a plain Ruby class, not a test). The rake task in `lib/tasks/categorization.rake` is a thin wrapper:

```ruby
namespace :categorization do
  desc "Benchmark categorization accuracy with synthetic data (requires Ollama)"
  task benchmark: :environment do
    unless OllamaService.available?
      puts "Error: Ollama is not available. Benchmark requires real model calls."
      exit 1
    end

    benchmark = CategorizationBenchmark.new
    results = benchmark.run
    benchmark.report(results)

    exit(results[:all_passed] ? 0 : 1)
  end
end
```

## Deployment to Existing Instances

### Migration Ordering

Migrations must run in this order (enforced by timestamp):

1. `CreateCategoryPatterns` — creates the table
2. `AddEmbeddingToTransactions` — adds nullable binary column (no data changes)
3. `MigrateMatchPatternsToCategoryPatterns` — data migration (must run after table exists)

All three are safe to run against a live database with zero downtime — no columns are removed, no data is deleted, no NOT NULL constraints added to existing columns.

### Seeds Update

The current `db/seeds.rb` unconditionally sets `category.match_patterns = patterns` on every run. After migration, this updates the deprecated column without touching the `category_patterns` table. Update seeds to detect which schema is active:

```ruby
income_category_data.each do |name, patterns|
  category = Category.find_or_initialize_by(name: name, category_type: "income")

  if CategoryPattern.table_exists?
    # New schema: write to CategoryPattern table
    category.save!
    if patterns.present?
      patterns.lines.map(&:strip).reject(&:blank?).each do |pattern|
        CategoryPattern.find_or_create_by!(
          category: category, pattern: pattern, source: "human"
        )
      end
    end
  else
    # Legacy schema: write to match_patterns text field
    category.match_patterns = patterns
    category.save!
  end
end
```

### Defensive Guards for Partial Deploy Window

During the window between deploying code and running migrations, new job classes and callbacks may be loaded before the database schema matches.

**`TransactionEmbeddingJob`**: Add rescue for missing column:

```ruby
rescue ActiveRecord::StatementInvalid => e
  Rails.logger.warn "TransactionEmbeddingJob: embedding column not yet available: #{e.message}"
end
```

**`PatternExtractionJob`** and **`CategorizationMaintenanceJob`**: Check table existence at the top of `perform`:

```ruby
def perform(...)
  unless CategoryPattern.table_exists?
    Rails.logger.info "#{self.class.name}: category_patterns table not yet created, skipping"
    return
  end
  # ...
end
```

**`recurring.yml` entries**: Solid Queue loads the schedule on boot. If the job class file exists but the database table doesn't, the table existence check ensures jobs exit cleanly until migrations run.

### Pre/Post-Deployment Verification

1. **Before deploying**: Run `rake categorization:benchmark` to establish baseline accuracy
2. **After deploying + migrating**: Run `rake categorization:benchmark` to verify accuracy is maintained
3. **After first hourly `PatternExtractionJob` run**: Run benchmark again to measure improvement from machine-learned patterns
4. Verify data migration: `CategoryPattern.human.count` should equal the total number of non-blank pattern lines across all categories

## Future Enhancements

1. **SetFit classifier**: Train a small sentence-transformer classifier as an alternative to Phase 2+3, served via a Python sidecar. Good learning project.
2. **Confidence scores in UI**: Show confidence level alongside category suggestions (high/medium/low based on which phase matched)
3. **User feedback loop**: Track when user overrides a suggestion — use as negative signal to adjust machine patterns
4. **Seasonal pattern detection**: Some merchants only appear in certain months (holiday shopping, etc.)
5. **Cross-account pattern sharing**: Patterns learned from one account's imports apply to all accounts

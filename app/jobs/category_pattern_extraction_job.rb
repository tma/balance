class CategoryPatternExtractionJob < ApplicationJob
  queue_as :default

  MINIMUM_OCCURRENCES = 2 # Merchant must appear 2+ times to become a pattern
  BATCH_SIZE = 10 # Max descriptions per LLM call

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
  def backfill_missing_embeddings
    unembedded = Transaction.where(embedding: nil).where.not(description: [ nil, "" ])
    count = unembedded.count
    return if count.zero?

    Rails.logger.info "CategoryPatternExtractionJob: backfilling #{count} missing embeddings"
    unembedded.find_each do |txn|
      TransactionEmbeddingJob.perform_later(txn.id)
    end
  end

  def process_transactions(scope)
    # Group transactions by category, extract merchant names
    scope.joins(:category)
         .where.not(description: [ nil, "" ])
         .where.not(category_id: nil)
         .group_by(&:category_id)
         .each do |cat_id, transactions|
      # Count how many transactions have each description
      description_counts = transactions.map(&:description).compact.tally
      unique_descriptions = description_counts.keys
      uncovered = unique_descriptions.reject { |d| covered_by_pattern?(d, cat_id) }
      next if uncovered.empty?

      # Extract merchant names from uncovered descriptions via LLM
      # Build description -> merchant mapping, then weight by transaction count
      merchant_counts = Hash.new(0)

      uncovered.each_slice(BATCH_SIZE) do |batch|
        merchants = extract_merchant_names(batch)
        batch.zip(merchants).each do |desc, merchant|
          next if merchant.blank?
          # Weight by how many transactions have this description
          merchant_counts[merchant] += description_counts[desc]
        end
      end

      create_patterns(cat_id, merchant_counts, transactions.size)
    end
  end

  def extract_merchant_names(descriptions)
    return [] unless OllamaService.available?

    prompt = <<~PROMPT
      Extract the merchant/company name from each transaction description.
      Strip store numbers, locations, dates, and reference codes.
      Return ONLY the stable merchant identifier.

      #{descriptions.each_with_index.map { |d, i| "#{i + 1}. \"#{d}\"" }.join("\n")}

      Return JSON array of merchant names in the same order:
      ["MERCHANT1", "MERCHANT2", ...]
    PROMPT

    response = OllamaService.generate_json(prompt)
    # LLM may return a plain array or wrap it in a hash like {"merchants" => [...]}
    result = response.is_a?(Hash) ? response.values.flatten : Array(response)
    result.map { |r| r.is_a?(String) ? r.strip : nil }.compact
  rescue OllamaService::Error => e
    Rails.logger.warn "CategoryPatternExtractionJob: LLM extraction failed: #{e.message}"
    []
  end

  def create_patterns(category_id, merchant_counts, total_transactions)
    merchant_counts.each do |merchant, count|
      next if merchant.blank? || count < MINIMUM_OCCURRENCES

      # Skip if a human pattern already covers this
      next if CategoryPattern.human.where(category_id: category_id)
                              .any? { |p| p.matches?(merchant) }

      existing = CategoryPattern.find_by(
        pattern: merchant,
        source: "machine",
        category_id: category_id
      )
      if existing
        existing.update!(
          confidence: (count.to_f / total_transactions).clamp(0, 1).round(2),
          match_count: [ existing.match_count, count ].max
        )
      else
        CategoryPattern.create!(
          pattern: merchant,
          source: "machine",
          category_id: category_id,
          confidence: (count.to_f / total_transactions).clamp(0, 1).round(2),
          match_count: count
        )
      end
    rescue ActiveRecord::RecordNotUnique
      # Race condition: another process created it, skip
      next
    end
  end

  def covered_by_pattern?(description, category_id)
    CategoryPattern.where(category_id: category_id)
                   .any? { |p| p.matches?(description) }
  end
end

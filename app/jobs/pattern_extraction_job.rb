class PatternExtractionJob < ApplicationJob
  queue_as :default

  MINIMUM_OCCURRENCES = 2 # Merchant must appear 2+ times to become a pattern
  BATCH_SIZE = 20 # Max descriptions per LLM call

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

    Rails.logger.info "PatternExtractionJob: backfilling #{count} missing embeddings"
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
      descriptions = transactions.map(&:description).compact.uniq
      uncovered = descriptions.reject { |d| covered_by_pattern?(d, cat_id) }
      next if uncovered.empty?

      # Process in batches to avoid oversized LLM prompts
      uncovered.each_slice(BATCH_SIZE) do |batch|
        merchants = extract_merchant_names(batch)
        create_patterns(cat_id, merchants, descriptions)
      end
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

      existing = CategoryPattern.find_by(
        pattern: merchant,
        source: "machine",
        category_id: category_id
      )
      if existing
        existing.update!(
          confidence: (count.to_f / descriptions.size).round(2),
          match_count: [ existing.match_count, count ].max
        )
      else
        CategoryPattern.create!(
          pattern: merchant,
          source: "machine",
          category_id: category_id,
          confidence: (count.to_f / descriptions.size).round(2),
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
                   .any? { |p| description.downcase.include?(p.pattern.downcase) }
  end
end

class CategorizationMaintenanceJob < ApplicationJob
  queue_as :default

  STALE_PATTERN_AGE = 30.days
  DRIFT_THRESHOLD = 0.6 # 60%+ of matched transactions re-categorized = stale

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
  def detect_recategorization_drift
    CategoryPattern.machine.where("match_count > 0").find_each do |pattern|
      sanitized = ActiveRecord::Base.sanitize_sql_like(pattern.pattern.downcase)
      matching_txns = Transaction.where("LOWER(description) LIKE ?", "%#{sanitized}%")
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
    CategoryPattern.machine
                   .group(:pattern)
                   .having("COUNT(DISTINCT category_id) > 1")
                   .pluck(:pattern)
                   .each do |pattern_text|
      duplicates = CategoryPattern.machine.where(pattern: pattern_text).order(match_count: :desc)
      # Keep the first (highest match_count), delete the rest
      keep = duplicates.first
      to_remove = duplicates.where.not(id: keep.id)

      count = to_remove.count
      to_remove.delete_all
      Rails.logger.info "CategorizationMaintenance: resolved conflict for \"#{pattern_text}\", " \
                        "kept category #{keep.category_id}, removed #{count} duplicates" if count > 0
    end
  end
end

# frozen_string_literal: true

# Provides coverage analysis for accounts with imports.
# Determines which date ranges are covered by imports and identifies gaps.
module AccountCoverage
  extend ActiveSupport::Concern

  GAP_THRESHOLD_DAYS = 7

  # Analyzes import coverage for this account.
  # Returns nil if account has no done imports with transactions.
  # Otherwise returns a hash with coverage details:
  #   - account: the account
  #   - first_date: earliest transaction date across all imports
  #   - last_date: latest transaction date across all imports
  #   - periods: array of merged coverage periods [{start:, end:}, ...]
  #   - gaps: array of gaps > GAP_THRESHOLD_DAYS [{start:, end:, days:}, ...]
  #   - complete?: true if no gaps exist
  def coverage_analysis
    return nil unless imports.done.exists?

    # Get date ranges from each done import's transactions
    periods = imports.done.includes(:transactions).filter_map do |import|
      dates = import.transactions.pluck(:date)
      next if dates.empty?
      { start: dates.min, end: dates.max }
    end

    return nil if periods.empty?

    # Sort by start date
    periods.sort_by! { |p| p[:start] }

    # Merge overlapping/adjacent periods
    merged = merge_periods(periods)

    # Find gaps > threshold
    gaps = find_gaps(merged)

    {
      account: self,
      first_date: merged.first[:start],
      last_date: merged.last[:end],
      periods: merged,
      gaps: gaps,
      complete?: gaps.empty?
    }
  end

  private

  # Merges periods that overlap or are within GAP_THRESHOLD_DAYS of each other.
  # Assumes periods are sorted by start date.
  def merge_periods(periods)
    return [] if periods.empty?

    merged = [ periods.first.dup ]

    periods[1..].each do |period|
      last = merged.last
      # Calculate gap between periods
      gap_days = (period[:start] - last[:end]).to_i - 1
      # If this period overlaps (gap < 0) or gap is within threshold, merge them
      if gap_days <= GAP_THRESHOLD_DAYS
        last[:end] = [ last[:end], period[:end] ].max
      else
        merged << period.dup
      end
    end

    merged
  end

  # Finds gaps between merged periods that are > GAP_THRESHOLD_DAYS.
  # Also flags a gap from the last period to today if stale.
  # Only returns gaps that are in the past (before today).
  def find_gaps(merged_periods)
    gaps = []
    today = Date.current

    # Gaps between periods
    merged_periods.each_cons(2) do |period_a, period_b|
      gap_start = period_a[:end] + 1.day
      gap_end = period_b[:start] - 1.day
      gap_days = (gap_end - gap_start).to_i + 1

      # Only flag past gaps > threshold
      next if gap_days <= GAP_THRESHOLD_DAYS
      next if gap_start > today

      gaps << {
        start: gap_start,
        end: [ gap_end, today ].min,
        days: gap_days
      }
    end

    # Gap from last period to today (stale data)
    if merged_periods.any?
      last_end = merged_periods.last[:end]
      gap_start = last_end + 1.day
      gap_days = (today - last_end).to_i

      if gap_days > GAP_THRESHOLD_DAYS
        gaps << {
          start: gap_start,
          end: today,
          days: gap_days
        }
      end
    end

    gaps
  end
end

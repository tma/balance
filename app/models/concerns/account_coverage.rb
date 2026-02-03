# frozen_string_literal: true

# Provides transaction coverage analysis for accounts.
# Determines which date ranges have transactions and identifies gaps.
module AccountCoverage
  extend ActiveSupport::Concern

  # Analyzes transaction coverage for this account.
  # Returns nil if:
  #   - Account has opted out of coverage tracking (expected_transaction_frequency is nil)
  #   - Account has no transactions
  # Otherwise returns a hash with coverage details:
  #   - account: the account
  #   - first_date: earliest transaction date
  #   - last_date: latest transaction date
  #   - periods: array of merged coverage periods [{start:, end:}, ...]
  #   - gaps: array of gaps > threshold [{start:, end:, days:}, ...]
  #   - complete?: true if no gaps exist
  #   - threshold: the gap threshold used for this account
  def coverage_analysis
    # Opt-out: nil frequency means no coverage tracking
    return nil if expected_transaction_frequency.nil?
    return nil unless transactions.exists?

    # Get all transaction dates for this account
    all_dates = transactions.pluck(:date).uniq.sort

    return nil if all_dates.empty?

    # Build periods from consecutive transaction dates
    # Each unique date becomes a single-day period, then we merge them
    periods = all_dates.map { |d| { start: d, end: d } }

    threshold = expected_transaction_frequency

    # Merge overlapping/adjacent periods within threshold
    merged = merge_periods(periods, threshold)

    # Find gaps > threshold
    gaps = find_gaps(merged, threshold)

    {
      account: self,
      first_date: merged.first[:start],
      last_date: merged.last[:end],
      periods: merged,
      gaps: gaps,
      complete?: gaps.empty?,
      threshold: threshold
    }
  end

  private

  # Merges periods that overlap or are within threshold of each other.
  # Assumes periods are sorted by start date.
  def merge_periods(periods, threshold)
    return [] if periods.empty?

    merged = [ periods.first.dup ]

    periods[1..].each do |period|
      last = merged.last
      # Calculate gap between periods
      gap_days = (period[:start] - last[:end]).to_i - 1
      # If this period overlaps (gap < 0) or gap is within threshold, merge them
      if gap_days <= threshold
        last[:end] = [ last[:end], period[:end] ].max
      else
        merged << period.dup
      end
    end

    merged
  end

  # Finds gaps between merged periods that are > threshold.
  # Also flags a gap from the last period to today if stale.
  # Only returns gaps that are in the past (before today).
  def find_gaps(merged_periods, threshold)
    gaps = []
    today = Date.current

    # Gaps between periods
    merged_periods.each_cons(2) do |period_a, period_b|
      gap_start = period_a[:end] + 1.day
      gap_end = period_b[:start] - 1.day
      gap_days = (gap_end - gap_start).to_i + 1

      # Only flag past gaps > threshold
      next if gap_days <= threshold
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

      if gap_days > threshold
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

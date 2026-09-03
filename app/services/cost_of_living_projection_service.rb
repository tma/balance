class CostOfLivingProjectionService
  PROVISIONAL_MONTHS = 6

  attr_reader :as_of, :period

  def initialize(as_of: Date.current, period: nil)
    @as_of = as_of
    @period = period || CostOfLivingPeriodService.new(as_of: as_of).call
  end

  def call
    detection = Transaction.detect_incomplete_months(scope: amount_scope)
    included_scope = detection[:scope]
    scope = included_scope.joins(:category)
      .where(categories: { category_type: "expense" })
      .includes(:category)
    converted = scope.where.not(amount_in_default_currency: nil).to_a
    included_months = included_scope.distinct.pluck(Arel.sql("strftime('%Y-%m', date)")).sort
    profiles = ExpenseProfile.includes(:category).where(status: "confirmed").to_a
    fixed_profiles = effective_fixed_profiles(profiles)

    assignments = converted.to_h do |transaction|
      matches = profiles.select do |profile|
        profile.category_id == transaction.category_id &&
          profile.matches_description?(transaction.description)
      end
      [ transaction.id, ExpenseProfile.best_match(matches, transaction.description) ]
    end

    variable_transactions = []
    classified_outflow = 0.to_d
    total_outflow = 0.to_d
    unclassified_signed = 0.to_d
    unclassified_by_category = Hash.new { |hash, category| hash[category] = 0.to_d }
    mixed_remainder_transaction_ids = []

    converted.each do |transaction|
      profile = assignments[transaction.id]
      total_outflow += transaction.amount_in_default_currency.to_d if transaction.expense?

      classification = transaction_classification(transaction, profile)
      if transaction.expense? && classification.present?
        classified_outflow += transaction.amount_in_default_currency.to_d
      end

      next if profile && fixed_profiles.include?(profile)

      signed = signed_expense_amount(transaction)
      if classification == "essential"
        variable_transactions << [ transaction, signed ]
      elsif classification.nil?
        unclassified_signed += signed
        unclassified_by_category[transaction.category] += signed
        mixed_remainder_transaction_ids << transaction.id if transaction.category.essentiality_mixed?
      end
    end

    variable = variable_summary(variable_transactions, included_months)
    fixed = fixed_profiles.sum { |profile| profile.annualized_amount }.round(2)
    annual = (fixed + variable[:annual]).round(2)
    unreviewed = annualize(unclassified_signed, included_months.size)
    completeness = total_outflow.positive? ? (classified_outflow / total_outflow * 100).round(1) : 0
    unreviewed_categories = unclassified_by_category.map do |category, total|
      { category: category, annual: annualize(total, included_months.size) }
    end.sort_by { |entry| -entry[:annual] }
    unclassified_categories = unreviewed_categories.reject { |entry| entry[:category].essentiality_mixed? }
    mixed_categories = unreviewed_categories.select { |entry| entry[:category].essentiality_mixed? }
    queue = ExpenseProfile.review_queue.includes(:category)
      .order(trailing_annual_amount: :desc, median_amount: :desc)
      .reject { |profile| profile.category.essentiality_excluded? }
    open_suggestions = queue.select(&:status_suggested?)
    classified_suggestion_impact = open_suggestions
      .reject { |profile| profile.category.essentiality.in?([ nil, "mixed" ]) }
      .sum(&:projected_annual_impact)
    unreviewed += classified_suggestion_impact
    bulk_eligible = queue.select do |profile|
      profile.status_suggested? &&
        profile.recurrence_confidence == "high" &&
        profile.detected_cadence.present? &&
        profile.median_amount.present? &&
        profile.essentiality.present? &&
        profile.essentiality == profile.category.essentiality &&
        (total_outflow.zero? || profile.projected_annual_impact / total_outflow < 0.05)
    end

    {
      annual: annual,
      monthly: (annual / 12).round(2),
      fixed_annual: fixed,
      fixed_monthly: (fixed / 12).round(2),
      variable_annual: variable[:annual],
      variable_monthly: (variable[:annual] / 12).round(2),
      typical_variable_month: variable[:median],
      fixed_profiles: fixed_profiles.sort_by { |profile| -profile.annualized_amount },
      variable_categories: variable[:categories],
      review_queue: queue,
      bulk_eligible_profiles: bulk_eligible,
      bulk_eligible_annual: bulk_eligible.sum(&:projected_annual_impact),
      categories: Category.expense.order(:name),
      classified_category_count: Category.expense.where.not(essentiality: nil).count,
      total_category_count: Category.expense.count,
      setup_started: Category.expense.where.not(essentiality: nil).exists?,
      complete: unclassified_categories.empty? && open_suggestions.empty?,
      completeness: completeness,
      unreviewed_annual: unreviewed,
      unreviewed_categories: unreviewed_categories,
      unclassified_categories: unclassified_categories,
      mixed_categories: mixed_categories,
      mixed_remainder_annual: mixed_categories.sum { |entry| entry[:annual] },
      mixed_remainder_transaction_ids: mixed_remainder_transaction_ids,
      open_suggestion_count: open_suggestions.size,
      included_months: included_months,
      excluded_months: detection[:excluded_months],
      provisional: included_months.size < PROVISIONAL_MONTHS,
      date_range: { from: scope.minimum(:date), to: scope.maximum(:date) },
      pending_conversion_count: amount_scope.joins(:category)
        .where(categories: { category_type: "expense" }, amount_in_default_currency: nil).count,
      period: period
    }
  end

  private

  def amount_scope
    @amount_scope ||= Transaction.where(
      date: period[:window_start]..period[:window_end]
    )
  end

  def effective_fixed_profiles(profiles)
    fixed = profiles.select(&:fixed_commitment?)
    fixed.reject do |profile|
      profile.review_flags.include?("superseded") ||
        fixed.any? do |other|
          next false if other == profile || other.category_id != profile.category_id

          overlapping = profile.matches_description?(other.merchant_pattern) ||
            other.matches_description?(profile.merchant_pattern)
          overlapping &&
            ([ other.merchant_pattern.length, -other.id ] <=>
              [ profile.merchant_pattern.length, -profile.id ]) == 1
        end
    end
  end

  def transaction_classification(transaction, profile)
    return "excluded" if transaction.category.essentiality_excluded?
    return profile.essentiality if profile

    essentiality = transaction.category.essentiality
    essentiality unless essentiality.in?([ nil, "mixed" ])
  end

  def signed_expense_amount(transaction)
    direction = transaction.expense? ? 1 : -1
    transaction.amount_in_default_currency.to_d * direction
  end

  def variable_summary(transactions, included_months)
    monthly = included_months.index_with { 0.to_d }
    categories = Hash.new(0.to_d)

    transactions.each do |transaction, signed|
      monthly[transaction.date.strftime("%Y-%m")] += signed
      categories[transaction.category] += signed
    end

    {
      annual: annualize(monthly.values.sum, included_months.size),
      median: median(monthly.values) || 0.to_d,
      categories: categories.map do |category, total|
        {
          category: category,
          annual: annualize(total, included_months.size)
        }
      end.sort_by { |entry| -entry[:annual] }
    }
  end

  def annualize(total, month_count)
    return 0.to_d if month_count.zero?

    (total / month_count * 12).round(2)
  end

  def median(values)
    return if values.empty?

    sorted = values.sort
    midpoint = sorted.length / 2
    sorted.length.odd? ? sorted[midpoint] : (sorted[midpoint - 1] + sorted[midpoint]) / 2.to_d
  end
end

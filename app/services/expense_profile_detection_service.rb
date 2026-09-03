class ExpenseProfileDetectionService
  EVIDENCE_MONTHS = 36
  AMOUNT_MONTHS = 12
  MATERIAL_OUTFLOW_RATIO = 0.01
  MAX_LLM_CANDIDATES = 50
  LLM_BATCH_SIZE = 10

  CADENCE_BANDS = {
    "monthly" => { range: 25..35, minimum_occurrences: 3 },
    "quarterly" => { range: 75..105, minimum_occurrences: 3 },
    "semiannual" => { range: 150..215, minimum_occurrences: 3 },
    "annual" => { range: 330..400, minimum_occurrences: 2 }
  }.freeze

  def self.classification_prompt(candidates)
    <<~PROMPT
      You are classifying expense streams for a bare-minimum cost-of-living estimate.

      ESSENTIALITY:
      - essential: required for basic housing, utilities, basic groceries, necessary healthcare,
        required insurance, minimum debt obligations, or basic transport/childcare needed to work.
      - discretionary: optional lifestyle spending such as entertainment, streaming/music/cloud
        subscriptions, restaurants and meal delivery, travel, fitness clubs, hobbies, and fashion.
      - excluded: movement of money rather than consumption, including transfers between owned
        accounts, savings/investment/retirement contributions, and credit-card payments whose
        underlying purchases are counted separately.
      Use both merchant and category. Classify the stream's purpose, not whether it repeats.

      RECURRENCE HINT:
      This is a mechanical field mapping, not a semantic classification:
      recurrence_hint = recurrence == "unknown" ?
        (occurrence_count == 1 ? "non_recurring" : "unknown") :
        "recurring"
      Ignore merchant, category, dates, and amount when producing recurrence_hint.
      This hint is advisory; use only recurring, non_recurring, or unknown.

      BOUNDARY EXAMPLES:
      - Fitness Club / Fitness / monthly => discretionary, recurring.
      - Restaurant / Dining / unknown with 8 occurrences => discretionary, unknown.
      - Pharmacy / Healthcare / unknown with 1 occurrence => essential, non_recurring.
      - Savings Transfer / Savings / annual => excluded, recurring.

      OUTPUT RULES:
      - Return valid JSON only, with one suggestions array.
      - Return every candidate exactly once using the unchanged candidate_id.
      - Input candidate count: #{candidates.size}. Output suggestion count must also be #{candidates.size}.
      - essentiality must be exactly essential, discretionary, or excluded.
      - recurrence_hint must be exactly recurring, non_recurring, or unknown.

      CANDIDATES:
      #{JSON.generate(candidates)}

      Apply the recurrence_hint formula literally to every candidate.

      JSON shape:
      {"suggestions":[{"candidate_id":"1","essentiality":"essential","recurrence_hint":"recurring"}]}
    PROMPT
  end

  def self.classification_schema(candidate_ids)
    {
      type: "object",
      additionalProperties: false,
      required: [ "suggestions" ],
      properties: {
        suggestions: {
          type: "array",
          minItems: candidate_ids.size,
          maxItems: candidate_ids.size,
          items: {
            type: "object",
            additionalProperties: false,
            required: %w[candidate_id essentiality recurrence_hint],
            properties: {
              candidate_id: { type: "string", enum: candidate_ids },
              essentiality: { type: "string", enum: ExpenseProfile::ESSENTIALITIES },
              recurrence_hint: { type: "string", enum: %w[recurring non_recurring unknown] }
            }
          }
        }
      }
    }
  end

  attr_reader :as_of, :period

  def initialize(as_of: Date.current, period: nil)
    @as_of = as_of
    @period = period || CostOfLivingPeriodService.new(as_of: as_of).call
  end

  def call
    context = amount_window_context
    candidates = build_candidates
    processed_ids = candidates.filter_map do |candidate|
      persist_candidate(candidate, context)
    end

    refresh_unmatched_profiles(processed_ids)
    apply_superseded_flags
    classify_suggestions

    ExpenseProfile.where(id: processed_ids)
  end

  private

  def evidence_start
    period_end - EVIDENCE_MONTHS.months
  end

  def amount_start
    period_end - AMOUNT_MONTHS.months
  end

  def period_end
    period[:data_complete_through].next_month.beginning_of_month
  end

  def evidence_transactions
    @evidence_transactions ||= Transaction.joins(:category)
      .includes(:category)
      .where(categories: { category_type: "expense" })
      .where(date: evidence_start...period_end)
      .where.not(description: [ nil, "" ])
      .where.not(amount_in_default_currency: nil)
      .order(:date, :id)
      .to_a
  end

  def amount_window_context
    base_scope = Transaction.where(date: amount_start...period_end)
    detection = Transaction.detect_incomplete_months(scope: base_scope)
    included_months = detection[:scope].distinct.pluck(Arel.sql("strftime('%Y-%m', date)")).to_set
    outflow = detection[:scope].joins(:category)
      .where(categories: { category_type: "expense" }, transaction_type: "expense")
      .where.not(amount_in_default_currency: nil)
      .sum(:amount_in_default_currency)
      .to_d

    {
      included_months: included_months,
      included_month_count: included_months.size,
      total_outflow: outflow,
      excluded_months: detection[:excluded_months]
    }
  end

  def build_candidates
    patterns = detection_patterns
    candidates = {}

    evidence_transactions.each do |transaction|
      match = best_pattern_match(patterns.fetch(transaction.category_id, []), transaction.description)
      pattern = match ? match[:pattern] : normalized_description(transaction.description)
      key = [ transaction.category_id, pattern.downcase ]

      candidates[key] ||= {
        category: transaction.category,
        pattern: pattern,
        patterned: match.present?,
        profile: match&.dig(:profile),
        transactions: []
      }
      candidates[key][:transactions] << transaction
    end

    candidates.values
  end

  def detection_patterns
    result = Hash.new { |hash, key| hash[key] = [] }

    ExpenseProfile.find_each do |profile|
      result[profile.category_id] << { pattern: profile.merchant_pattern, profile: profile }
    end

    CategoryPattern.joins(:category)
      .where(categories: { category_type: "expense" })
      .find_each do |pattern|
        result[pattern.category_id] << { pattern: pattern.pattern, profile: nil }
      end

    result.transform_values do |entries|
      entries.uniq { |entry| entry[:pattern].downcase }
    end
  end

  def best_pattern_match(patterns, description)
    patterns.select { |entry| pattern_matches?(entry[:pattern], description) }
      .max_by do |entry|
        profile_priority = entry[:profile] ? 1 : 0
        profile_id_priority = entry[:profile] ? -entry[:profile].id : 0
        [ entry[:pattern].length, profile_priority, profile_id_priority ]
      end
  end

  def pattern_matches?(pattern, description)
    description.to_s.match?(/\b#{Regexp.escape(pattern)}\b/i)
  end

  def normalized_description(description)
    description.to_s.strip.sub(/\A\W+/, "").sub(/\W+\z/, "")
  end

  def persist_candidate(candidate, context)
    return if candidate[:category].essentiality_excluded?

    evidence = recurrence_evidence(candidate[:transactions])
    trailing = trailing_transactions(candidate[:transactions], context[:included_months])
    trailing_outflow = trailing.select(&:expense?).sum { |transaction| transaction.amount_in_default_currency.to_d }
    material = context[:total_outflow].positive? &&
      trailing_outflow / context[:total_outflow] >= MATERIAL_OUTFLOW_RATIO
    material_candidate = !candidate[:patterned] &&
      candidate[:category].essentiality.in?([ nil, "mixed" ]) &&
      material
    queue_worthy = %w[high medium].include?(evidence[:confidence]) ||
      material_candidate

    profile = candidate[:profile] || ExpenseProfile.find_by(
      category_id: candidate[:category].id,
      merchant_pattern: candidate[:pattern]
    )
    return unless profile || candidate[:patterned] || queue_worthy
    return profile.id if profile&.status_dismissed?

    profile ||= ExpenseProfile.new(
      category: candidate[:category],
      merchant_pattern: candidate[:pattern],
      source: "machine",
      status: "suggested"
    )

    attributes = evidence.merge(
      trailing_annual_amount: annualize_window_total(
        signed_total(trailing),
        context[:included_month_count]
      ),
      detected_at: Time.current
    )
    attributes[:essentiality] = suggested_essentiality(candidate[:category]) if profile.new_record?
    attributes[:review_flags] = review_flags(profile, evidence, material: material_candidate)
    profile.update!(attributes)
    profile.id
  end

  def recurrence_evidence(transactions)
    occurrences = transactions.select(&:expense?)
      .group_by(&:date)
      .map do |date, transactions_on_date|
        amount = transactions_on_date.sum { |transaction| transaction.amount_in_default_currency.to_d }
        [ date, amount ]
      end
      .sort_by(&:first)
    dates = occurrences.map(&:first)
    amounts = occurrences.map(&:last)
    intervals = dates.each_cons(2).map { |first, second| (second - first).to_i }
    median_interval = median(intervals)
    cadence = detected_cadence(median_interval, occurrences.size)
    interval_cv = coefficient_of_variation(intervals)
    overdue = cadence.present? && overdue?(dates.last, cadence)
    confidence = recurrence_confidence(cadence, occurrences.size, interval_cv, overdue)
    cadence = nil if confidence == "low"
    recent_amounts = amounts.last(3)

    {
      occurrence_count: occurrences.size,
      first_seen_on: dates.first,
      last_seen_on: dates.last,
      median_amount: median(recent_amounts),
      amount_cv: coefficient_of_variation(amounts),
      interval_cv: interval_cv,
      detected_cadence: cadence,
      recurrence_confidence: confidence
    }
  end

  def detected_cadence(median_interval, occurrence_count)
    return if median_interval.nil?

    CADENCE_BANDS.find do |_, config|
      config[:range].cover?(median_interval) && occurrence_count >= config[:minimum_occurrences]
    end&.first
  end

  def recurrence_confidence(cadence, occurrence_count, interval_cv, overdue)
    return "low" if cadence.blank?
    return "medium" if cadence == "annual" && occurrence_count == 2
    return "high" if occurrence_count >= 3 && interval_cv <= 0.15 && !overdue
    return "medium" if interval_cv <= 0.30

    "low"
  end

  def overdue?(last_seen_on, cadence)
    return false if last_seen_on.nil?

    upper_bound = CADENCE_BANDS.fetch(cadence)[:range].end
    (period_end - last_seen_on).to_i > upper_bound * 1.5
  end

  def review_flags(profile, evidence, material:)
    return [ "material" ] if profile.new_record? && material
    return Array(profile.review_flags) unless profile.status_confirmed?

    flags = []
    if profile.confirmed_amount.present? && evidence[:median_amount].present?
      change = (evidence[:median_amount] - profile.confirmed_amount).abs / profile.confirmed_amount
      flags << "amount_change" if change >= 0.20
    end
    if evidence[:detected_cadence].present? && evidence[:detected_cadence] != profile.cadence
      flags << "cadence_change"
    end
    flags << "overdue" if profile.cadence.present? && overdue?(evidence[:last_seen_on], profile.cadence)
    flags
  end

  def trailing_transactions(transactions, included_months)
    transactions.select do |transaction|
      transaction.date >= amount_start && included_months.include?(transaction.date.strftime("%Y-%m"))
    end
  end

  def signed_total(transactions)
    transactions.sum do |transaction|
      direction = transaction.expense? ? 1 : -1
      transaction.amount_in_default_currency.to_d * direction
    end
  end

  def annualize_window_total(total, month_count)
    return 0.to_d if month_count.zero?

    (total / month_count * 12).round(2)
  end

  def median(values)
    return if values.empty?

    sorted = values.sort
    midpoint = sorted.length / 2
    sorted.length.odd? ? sorted[midpoint] : (sorted[midpoint - 1] + sorted[midpoint]) / 2.to_d
  end

  def coefficient_of_variation(values)
    return 0.to_d if values.size <= 1

    mean = values.sum.to_d / values.size
    return 0.to_d if mean.zero?

    variance = values.sum { |value| (value.to_d - mean)**2 } / values.size
    (Math.sqrt(variance.to_f) / mean.abs).round(4)
  end

  def suggested_essentiality(category)
    category.essentiality if category.essentiality.in?(ExpenseProfile::ESSENTIALITIES)
  end

  def refresh_unmatched_profiles(processed_ids)
    ExpenseProfile.where.not(status: "dismissed").where.not(id: processed_ids).find_each do |profile|
      transactions = evidence_transactions.select do |transaction|
        transaction.category_id == profile.category_id &&
          profile.matches_description?(transaction.description)
      end
      next if transactions.any?
      next unless profile.status_confirmed? && profile.cadence.present?

      flags = profile.review_flags - [ "overdue" ]
      flags << "overdue" if overdue?(profile.last_seen_on, profile.cadence)
      profile.update!(review_flags: flags.uniq)
    end
  end

  def apply_superseded_flags
    profiles = ExpenseProfile.includes(:category).where(status: "confirmed").select(&:fixed_commitment?)
    superseded_ids = profiles.group_by(&:category_id).values.flat_map do |category_profiles|
      category_profiles.combination(2).filter_map do |first, second|
        next unless patterns_overlap?(first, second)

        winner = [ first, second ].max_by { |profile| [ profile.merchant_pattern.length, -profile.id ] }
        (winner == first ? second : first).id
      end
    end.to_set

    profiles.each do |profile|
      flags = profile.review_flags - [ "superseded" ]
      flags << "superseded" if superseded_ids.include?(profile.id)
      profile.update!(review_flags: flags.uniq) if flags != profile.review_flags
    end
  end

  def patterns_overlap?(first, second)
    first.matches_description?(second.merchant_pattern) ||
      second.matches_description?(first.merchant_pattern)
  end

  def classify_suggestions
    profiles = ExpenseProfile.review_queue
      .where(status: "suggested", essentiality: nil)
      .order(trailing_annual_amount: :desc)
      .limit(MAX_LLM_CANDIDATES)
      .to_a
    return if profiles.empty? || !OllamaService.model_available?

    profiles.each_slice(LLM_BATCH_SIZE) { |batch| classify_batch(batch) }
  end

  def classify_batch(profiles)
    response = OllamaService.generate_json(
      classification_prompt(profiles),
      schema: self.class.classification_schema(profiles.map { |profile| profile.id.to_s })
    )
    suggestions = response.is_a?(Hash) ? response["suggestions"] : nil
    return unless suggestions.is_a?(Array)

    duplicate_ids = suggestions.map { |suggestion| suggestion["candidate_id"].to_s }
      .tally
      .select { |_, count| count > 1 }
      .keys
    profiles_by_id = profiles.index_by { |profile| profile.id.to_s }

    suggestions.each do |suggestion|
      candidate_id = suggestion["candidate_id"].to_s
      profile = profiles_by_id[candidate_id]
      next if profile.nil? || duplicate_ids.include?(candidate_id)
      next unless suggestion["essentiality"].in?(ExpenseProfile::ESSENTIALITIES)
      next unless suggestion["recurrence_hint"].in?(%w[recurring non_recurring unknown])

      profile.update!(essentiality: suggestion["essentiality"])
    end
  rescue OllamaService::Error => e
    Rails.logger.warn "ExpenseProfileDetectionService: classification failed: #{e.message}"
  end

  def classification_prompt(profiles)
    candidates = profiles.map do |profile|
      {
        candidate_id: profile.id.to_s,
        merchant: profile.merchant_pattern,
        category: profile.category.name,
        occurrence_count: profile.occurrence_count,
        first_seen_on: profile.first_seen_on,
        last_seen_on: profile.last_seen_on,
        amount_range: profile.median_amount,
        recurrence: profile.detected_cadence || "unknown"
      }
    end

    self.class.classification_prompt(candidates)
  end
end

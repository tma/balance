# frozen_string_literal: true

class CostOfLivingPromptBenchmark
  BATCH_SIZE = 10
  DEFAULT_ROUNDS = 3
  THRESHOLDS = {
    essentiality: 0.85,
    recurrence: 0.90,
    schema: 1.0,
    stability: 0.90
  }.freeze

  CASES = [
    [ "Rent payment", "Rent", 12, "monthly", "essential", "recurring" ],
    [ "Monthly mortgage payment", "Mortgage", 12, "monthly", "essential", "recurring" ],
    [ "City Electric Company", "Utilities", 12, "monthly", "essential", "recurring" ],
    [ "Municipal Water Utility", "Utilities", 4, "quarterly", "essential", "recurring" ],
    [ "Health insurance premium", "Healthcare", 12, "monthly", "essential", "recurring" ],
    [ "Prescription Pharmacy", "Healthcare", 1, "unknown", "essential", "non_recurring" ],
    [ "Neighborhood Supermarket", "Groceries", 18, "unknown", "essential", "unknown" ],
    [ "Monthly Transit Pass", "Transportation", 12, "monthly", "essential", "recurring" ],
    [ "Auto insurance", "Insurance", 3, "semiannual", "essential", "recurring" ],
    [ "Daycare Center", "Childcare", 12, "monthly", "essential", "recurring" ],
    [ "Mobile Phone Service", "Utilities", 12, "monthly", "essential", "recurring" ],
    [ "Student loan payment", "Debt Payments", 12, "monthly", "essential", "recurring" ],
    [ "Netflix", "Subscriptions", 12, "monthly", "discretionary", "recurring" ],
    [ "Spotify", "Subscriptions", 12, "monthly", "discretionary", "recurring" ],
    [ "Downtown Restaurant", "Dining", 8, "unknown", "discretionary", "unknown" ],
    [ "Fitness Club", "Fitness", 12, "monthly", "discretionary", "recurring" ],
    [ "Cinema Tickets", "Entertainment", 1, "unknown", "discretionary", "non_recurring" ],
    [ "Vacation Hotel", "Travel", 1, "unknown", "discretionary", "non_recurring" ],
    [ "Video Game Store", "Entertainment", 1, "unknown", "discretionary", "non_recurring" ],
    [ "Fashion Boutique", "Clothing", 3, "unknown", "discretionary", "unknown" ],
    [ "Golf Club Membership", "Recreation", 12, "monthly", "discretionary", "recurring" ],
    [ "Meal Delivery Membership", "Dining", 12, "monthly", "discretionary", "recurring" ],
    [ "Transfer to Savings", "Savings", 12, "monthly", "excluded", "recurring" ],
    [ "Brokerage Contribution", "Investments", 12, "monthly", "excluded", "recurring" ],
    [ "Credit Card Payment", "Transfers", 12, "monthly", "excluded", "recurring" ],
    [ "Internal Bank Transfer", "Transfers", 8, "unknown", "excluded", "unknown" ],
    [ "Retirement Contribution", "Savings", 12, "monthly", "excluded", "recurring" ],
    [ "Emergency Fund Transfer", "Savings", 1, "unknown", "excluded", "non_recurring" ],
    [ "Amazon Prime", "Subscriptions", 12, "monthly", "discretionary", "recurring" ],
    [ "Amazon Medical Supplies", "Healthcare", 1, "unknown", "essential", "non_recurring" ],
    [ "Amazon Movie Rental", "Entertainment", 1, "unknown", "discretionary", "non_recurring" ],
    [ "Costco Wholesale", "Groceries", 10, "unknown", "essential", "unknown" ],
    [ "Shell Fuel", "Gas", 16, "unknown", "essential", "unknown" ],
    [ "Cloud Storage Plan", "Subscriptions", 12, "monthly", "discretionary", "recurring" ],
    [ "Annual Savings Transfer", "Savings", 2, "annual", "excluded", "recurring" ],
    [ "Dental Emergency", "Healthcare", 1, "unknown", "essential", "non_recurring" ]
  ].each_with_index.map do |values, index|
    merchant, category, occurrence_count, recurrence, essentiality, recurrence_hint = values
    {
      candidate_id: (index + 1).to_s,
      merchant: merchant,
      category: category,
      occurrence_count: occurrence_count,
      first_seen_on: "2025-01-01",
      last_seen_on: "2026-08-01",
      amount_range: 100,
      recurrence: recurrence,
      expected_essentiality: essentiality,
      expected_recurrence_hint: recurrence_hint
    }
  end.freeze

  attr_reader :rounds, :model

  def initialize(rounds: ENV.fetch("ROUNDS", DEFAULT_ROUNDS).to_i)
    @rounds = rounds
    @model = Rails.application.config.ollama.model
  end

  def run
    raise "Configured model #{model.inspect} is unavailable" unless OllamaService.model_available?

    runs = Array.new(rounds) { run_round }
    result = score(runs)
    report(result)
    result
  end

  private

  def run_round
    CASES.each_slice(BATCH_SIZE).each_with_object({}) do |batch, output|
      candidates = batch.map { |entry| entry.except(:expected_essentiality, :expected_recurrence_hint) }
      response = OllamaService.generate_json(
        ExpenseProfileDetectionService.classification_prompt(candidates),
        schema: ExpenseProfileDetectionService.classification_schema(candidates.pluck(:candidate_id))
      )
      suggestions = response.is_a?(Hash) ? response["suggestions"] : nil
      next unless suggestions.is_a?(Array)

      suggestions.each do |suggestion|
        id = suggestion["candidate_id"].to_s
        output[id] ||= []
        output[id] << suggestion
      end
    end
  end

  def score(runs)
    essentiality_correct = 0
    recurrence_correct = 0
    schema_correct = 0
    stable_total = 0.to_d
    failures = []

    CASES.each do |test_case|
      id = test_case[:candidate_id]
      predictions = runs.map do |run|
        entries = run.fetch(id, [])
        entries.one? ? entries.first : nil
      end
      valid = predictions.map { |prediction| valid_prediction?(prediction) }
      schema_correct += valid.count(true)
      valid_predictions = predictions.zip(valid).filter_map { |prediction, is_valid| prediction if is_valid }
      essentiality_correct += valid_predictions.count do |prediction|
        prediction["essentiality"] == test_case[:expected_essentiality]
      end
      recurrence_correct += valid_predictions.count do |prediction|
        prediction["recurrence_hint"] == test_case[:expected_recurrence_hint]
      end
      stable_total += stability(valid_predictions)

      next if valid_predictions.size == rounds &&
        valid_predictions.all? { |prediction| prediction["essentiality"] == test_case[:expected_essentiality] } &&
        valid_predictions.all? { |prediction| prediction["recurrence_hint"] == test_case[:expected_recurrence_hint] }

      failures << {
        merchant: test_case[:merchant],
        category: test_case[:category],
        expected: [ test_case[:expected_essentiality], test_case[:expected_recurrence_hint] ],
        actual: predictions.map { |prediction|
          prediction && [ prediction["essentiality"], prediction["recurrence_hint"] ]
        }
      }
    end

    total = CASES.size * rounds
    metrics = {
      essentiality: essentiality_correct.to_f / total,
      recurrence: recurrence_correct.to_f / total,
      schema: schema_correct.to_f / total,
      stability: (stable_total / CASES.size).to_f
    }

    {
      model: model,
      rounds: rounds,
      cases: CASES.size,
      metrics: metrics,
      failures: failures,
      all_passed: THRESHOLDS.all? { |metric, threshold| metrics.fetch(metric) >= threshold }
    }
  end

  def valid_prediction?(prediction)
    prediction.is_a?(Hash) &&
      prediction["essentiality"].in?(ExpenseProfile::ESSENTIALITIES) &&
      prediction["recurrence_hint"].in?(%w[recurring non_recurring unknown])
  end

  def stability(predictions)
    return 0.to_d if predictions.empty?

    pairs = predictions.map { |prediction| [ prediction["essentiality"], prediction["recurrence_hint"] ] }
    pairs.tally.values.max.to_d / rounds
  end

  def report(result)
    puts "Cost of Living Ollama Prompt Benchmark"
    puts "Model: #{result[:model]}"
    puts "Cases: #{result[:cases]} x #{result[:rounds]} rounds"
    result[:metrics].each do |metric, value|
      threshold = THRESHOLDS.fetch(metric)
      status = value >= threshold ? "PASS" : "FAIL"
      puts "#{metric.to_s.humanize}: #{(value * 100).round(1)}% #{status} (threshold: #{(threshold * 100).round}%)"
    end

    if result[:failures].any?
      puts "\nMismatches or invalid responses:"
      result[:failures].each do |failure|
        puts "- #{failure[:merchant]} [#{failure[:category]}]"
        puts "  expected: #{failure[:expected].join('/')}"
        puts "  actual:   #{failure[:actual].inspect}"
      end
    end

    puts "\nResult: #{result[:all_passed] ? 'ALL PASSED' : 'SOME FAILED'}"
  end
end

# frozen_string_literal: true

# Benchmark runner to compare Ollama LLM models for Balance's tasks.
# Test cases are aligned with the actual production prompts from:
#   - CsvMappingAnalyzerService#build_prompt (CSV column mapping)
#   - CategoryMatchingService#build_llm_prompt (single transaction categorization)
#   - CategoryPatternExtractionJob#extract_merchant_names (merchant extraction)
#
# NOT part of `rails test` — run via: rake llm:benchmark
#
# How it works:
#   1. Checks which requested models are available in Ollama
#   2. Runs each model against a fixed set of test cases with validation
#   3. Saves results incrementally to tmp/llm_benchmark_results.json
#   4. Prints comparison table with accuracy and timing
#
# Re-running skips already-tested models (delete results file to reset).
class LlmBenchmark
  RESULTS_FILE = "tmp/llm_benchmark_results.json"

  DEFAULT_MODELS = %w[llama3.1:8b mistral:7b mistral-nemo:12b gemma3:4b gemma3:12b gemma3n:e4b qwen3:4b qwen3:8b].freeze

  # =========================================================================
  # Prompt builders — mirrors from production code
  # =========================================================================

  # Mirrors CsvMappingAnalyzerService#build_prompt exactly
  def self.csv_mapping_prompt(sample_csv)
    <<~PROMPT
      Analyze this CSV and identify the column mappings for a financial transaction import.

      CSV SAMPLE (header + representative rows):
      ```
      #{sample_csv}
      ```

      TASK: Identify the columns and formats by examining BOTH headers AND data values.

      NOTE: Some CSVs have GROUPED TRANSACTIONS where:
      - A "header row" has the date and total amount
      - Following "detail rows" have NO date but individual amounts and descriptions
      - Detail rows inherit the date from their header row
      Look for rows with empty date columns but populated amount/description in different columns.

      1. DATE COLUMN (IMPORTANT):#{" "}
         - Choose the date when the transaction ACTUALLY HAPPENED
         - Prefer columns named: "Date", "Transaction Date", "Datum", "Buchungsdatum", "Trans Date"
         - AVOID accounting/settlement dates: "ValutaDate", "Valuta", "Value Date", "Posting Date", "Settlement Date", "Effective Date"
         - These valuta/settlement dates are when money moves between banks, NOT when you made the purchase
         - If you see both "Date" and "ValutaDate", always choose "Date"

      2. DESCRIPTION COLUMNS (CRITICAL - ALWAYS CHECK FOR SECONDARY):#{" "}
         - Primary: The main transaction type or merchant name. Common names:
           * German: "Buchungstext", "Beschreibung", "Text", "Verwendungszweck"
           * English: "Description", "MerchantName", "Merchant", "Payee", "Name", "Narrative"
         - Secondary: ALWAYS look for a secondary column with additional details! Common names:
           * German: "Zahlungszweck", "Verwendungszweck", "Details", "Bemerkung", "Mitteilung"
           * English: "Memo", "Details", "Notes", "Reference", "Purpose", "Narrative"
         - If you see columns like "Zahlungszweck" or "Details" that contain meaningful text, ALWAYS include as secondary
         - IGNORE currency columns like "Whg", "Currency", "Währung" - these contain currency codes (CHF, EUR, USD), not descriptions
         - IGNORE pure reference/ID columns like "Referenz", "Referenznummer", "TransactionId", "CardId" that only contain IDs

      3. AMOUNT COLUMNS - Look at the data carefully:
         - If ONE column has both positive and negative numbers → "single" (amount_column)
         - If TWO separate columns for money out/in (one often empty per row) → "split" (debit_column + credit_column)
         - German: "Soll" = debit (expense), "Haben" = credit (income), "Belastung" = debit, "Gutschrift" = credit
         - English: "Debit"/"Outflow" = expense, "Credit"/"Inflow" = income

      4. DATE FORMAT - Look at actual date values:
         - "DD.MM.YYYY" for 31.12.2024
         - "DD/MM/YYYY" for 31/12/2024
         - "MM/DD/YYYY" for 12/31/2024
         - "YYYY-MM-DD" for 2024-12-31

      5. AMOUNT FORMAT - Look at actual numbers in the data:
         - "eu" if comma is decimal: "1.234,56" or "45,80"
         - "us" if dot is decimal: "1,234.56" or "45.80" or "£2,850.00"
         - "plain" if no thousands separator: "1234.56"
         - IMPORTANT: Look at the actual numbers, not the language of headers!

      Return JSON:
      {
        "date_column": "exact column name",
        "description_column": "primary description column",
        "description_secondary_column": "optional secondary column or null",
        "amount_type": "single" or "split",
        "amount_column": "column name" (only if single),
        "debit_column": "column name" (only if split),
        "credit_column": "column name" (only if split),
        "date_format": "DD.MM.YYYY",
        "amount_format": "eu" or "us" or "plain"
      }
    PROMPT
  end

  # Mirrors CategoryMatchingService#build_llm_prompt
  # Production includes few-shot examples from transaction history;
  # here we provide synthetic examples to test the same prompt shape.
  def self.single_categorization_prompt(txn_type, description, amount, categories, few_shot_examples: [])
    examples_text = if few_shot_examples.any?
      "SIMILAR TRANSACTIONS YOU'VE CATEGORIZED BEFORE:\n" +
      few_shot_examples.map { |e| "- \"#{e[:description]}\" -> #{e[:category]}" }.join("\n") + "\n\n"
    else
      ""
    end

    <<~PROMPT
      Categorize this transaction into ONE of the given categories.

      #{examples_text}TRANSACTION: [#{txn_type.upcase}] #{description} (#{amount})

      CATEGORIES: #{categories.join(", ")}

      Return JSON with the exact category name:
      {"category": "category name"}
    PROMPT
  end

  # Mirrors CategoryPatternExtractionJob#extract_merchant_names
  def self.merchant_extraction_prompt(descriptions)
    <<~PROMPT
      Extract the merchant/company name from each transaction description.
      Strip store numbers, locations, dates, and reference codes.
      Return ONLY the stable merchant identifier.

      #{descriptions.each_with_index.map { |d, i| "#{i + 1}. \"#{d}\"" }.join("\n")}

      Return JSON array of merchant names in the same order:
      ["MERCHANT1", "MERCHANT2", ...]
    PROMPT
  end

  # Helper to extract merchant array from various response formats
  # Mirrors CategoryPatternExtractionJob line 81
  def self.extract_merchants(response)
    result = response.is_a?(Hash) ? response.values.flatten : Array(response)
    result.map { |r| r.is_a?(String) ? r.strip : nil }.compact
  end

  # =========================================================================
  # TEST CASES — Aligned with actual Balance production prompts
  # =========================================================================
  TEST_CASES = [
    # -----------------------------------------------------------------------
    # CSV COLUMN MAPPING — CsvMappingAnalyzerService#build_prompt
    # -----------------------------------------------------------------------
    {
      name: "CSV Mapping: German bank (single amount)",
      category: "CSV Column Mapping",
      prompt: csv_mapping_prompt(
        "Buchungsdatum;Valutadatum;Buchungstext;Zahlungszweck;Betrag;Saldo\n" \
        "15.01.2025;16.01.2025;Lastschrift;NETFLIX SARL;-17.99;1234.56\n" \
        "14.01.2025;14.01.2025;Gutschrift;LOHN JANUAR 2025;3500.00;1252.55\n" \
        "13.01.2025;13.01.2025;Kartenzahlung;MIGROS BASEL;-45.80;-2247.45"
      ),
      expected: {
        date_column: "Buchungsdatum",
        description_column: "Buchungstext",
        description_secondary_column: "Zahlungszweck",
        amount_type: "single",
        amount_column: "Betrag",
        date_format: "DD.MM.YYYY",
        amount_format: "plain"
      },
      validate: ->(response, expected) {
        score = 0
        score += 1 if response["date_column"]&.downcase == expected[:date_column].downcase
        score += 1 if response["date_column"]&.downcase != "valutadatum"
        score += 1 if response["description_column"]&.downcase == expected[:description_column].downcase
        score += 1 if response["description_secondary_column"]&.downcase == expected[:description_secondary_column].downcase
        score += 1 if response["amount_type"] == expected[:amount_type]
        score += 1 if response["amount_column"]&.downcase == expected[:amount_column].downcase
        score += 1 if response["amount_format"] == expected[:amount_format] || response["amount_format"] == "eu"
        { score: score, max: 7 }
      }
    },
    {
      name: "CSV Mapping: English bank (split amounts)",
      category: "CSV Column Mapping",
      prompt: csv_mapping_prompt(
        "Date,Description,Memo,Debit,Credit,Balance\n" \
        "2025-01-15,Netflix,Monthly subscription,17.99,,1234.56\n" \
        "2025-01-14,Salary,January wages,,3500.00,1252.55\n" \
        "2025-01-13,Grocery Store,Weekly shopping,89.50,,747.45"
      ),
      expected: {
        date_column: "Date",
        description_column: "Description",
        description_secondary_column: "Memo",
        amount_type: "split",
        debit_column: "Debit",
        credit_column: "Credit",
        date_format: "YYYY-MM-DD",
        amount_format: "plain"
      },
      validate: ->(response, expected) {
        score = 0
        score += 1 if response["date_column"]&.downcase == expected[:date_column].downcase
        score += 1 if response["description_column"]&.downcase == expected[:description_column].downcase
        score += 1 if response["description_secondary_column"]&.downcase == expected[:description_secondary_column].downcase
        score += 1 if response["amount_type"] == expected[:amount_type]
        score += 1 if response["debit_column"]&.downcase == expected[:debit_column].downcase
        score += 1 if response["credit_column"]&.downcase == expected[:credit_column].downcase
        { score: score, max: 6 }
      }
    },
    {
      name: "CSV Mapping: German Soll/Haben (EU format)",
      category: "CSV Column Mapping",
      prompt: csv_mapping_prompt(
        "Datum;Beschreibung;Verwendungszweck;Soll;Haben;Saldo\n" \
        "15.01.2025;Lastschrift;NETFLIX SARL;17,99;;1234,56\n" \
        "14.01.2025;Gutschrift;LOHN JANUAR 2025;;3500,00;1252,55\n" \
        "13.01.2025;Kartenzahlung;MIGROS BASEL;45,80;;-2247,45"
      ),
      expected: {
        date_column: "Datum",
        description_column: "Beschreibung",
        description_secondary_column: "Verwendungszweck",
        amount_type: "split",
        debit_column: "Soll",
        credit_column: "Haben",
        date_format: "DD.MM.YYYY",
        amount_format: "eu"
      },
      validate: ->(response, expected) {
        score = 0
        score += 1 if response["date_column"]&.downcase == expected[:date_column].downcase
        score += 1 if response["description_column"]&.downcase == expected[:description_column].downcase
        score += 1 if response["description_secondary_column"]&.downcase == expected[:description_secondary_column].downcase
        score += 1 if response["amount_type"] == expected[:amount_type]
        score += 1 if response["debit_column"]&.downcase == expected[:debit_column].downcase
        score += 1 if response["credit_column"]&.downcase == expected[:credit_column].downcase
        score += 1 if response["amount_format"] == expected[:amount_format]
        { score: score, max: 7 }
      }
    },

    # -----------------------------------------------------------------------
    # SINGLE CATEGORIZATION — CategoryMatchingService#build_llm_prompt
    # -----------------------------------------------------------------------
    {
      name: "Categorization: grocery store (with history)",
      category: "Single Categorization",
      prompt: single_categorization_prompt(
        "expense", "MIGROS BASEL STEINENVORSTADT", 67.85,
        %w[Groceries Shopping Dining],
        few_shot_examples: [
          { description: "COOP PRATTELN #1234", category: "Groceries" },
          { description: "MANOR AG BASEL", category: "Shopping" },
          { description: "RESTAURANT ZUM OCHSEN", category: "Dining" }
        ]
      ),
      expected: "Groceries",
      validate: ->(response, expected) {
        return { score: 0, max: 1 } unless response.is_a?(Hash)
        actual = (response["category"] || response["name"] || response.values.first).to_s
        score = actual.downcase.include?(expected.downcase) ? 1 : 0
        { score: score, max: 1 }
      }
    },
    {
      name: "Categorization: gas station (ambiguous merchant)",
      category: "Single Categorization",
      prompt: single_categorization_prompt(
        "expense", "COOP PRONTO TANKSTELLE", 95.50,
        %w[Groceries Transportation Shopping],
        few_shot_examples: [
          { description: "SHELL OIL 57442634829", category: "Transportation" },
          { description: "MIGROS BASEL", category: "Groceries" },
          { description: "COOP SUPERMARKT LIESTAL", category: "Groceries" }
        ]
      ),
      expected: "Transportation",
      validate: ->(response, _expected) {
        return { score: 0, max: 1 } unless response.is_a?(Hash)
        actual = (response["category"] || response["name"] || response.values.first).to_s.downcase
        # Transportation preferred (it's a gas station), groceries acceptable (COOP brand)
        score = actual.include?("transportation") ? 1 : (actual.include?("groceries") ? 0.5 : 0)
        { score: score, max: 1 }
      }
    },
    {
      name: "Categorization: subscription (no history)",
      category: "Single Categorization",
      prompt: single_categorization_prompt(
        "expense", "NETFLIX SARL", 17.99,
        %w[Entertainment Subscriptions Shopping]
      ),
      expected: %w[Entertainment Subscriptions],
      validate: ->(response, expected) {
        return { score: 0, max: 1 } unless response.is_a?(Hash)
        actual = (response["category"] || response["name"] || response.values.first).to_s.downcase
        score = expected.any? { |e| actual.include?(e.downcase) } ? 1 : 0
        { score: score, max: 1 }
      }
    },
    {
      name: "Categorization: salary income",
      category: "Single Categorization",
      prompt: single_categorization_prompt(
        "income", "LOHN JANUAR 2025 ARBEITGEBER AG", 5200.00,
        %w[Salary Freelance Other],
        few_shot_examples: [
          { description: "GEHALT DEZEMBER 2024", category: "Salary" },
          { description: "UPWORK PAYMENT", category: "Freelance" }
        ]
      ),
      expected: "Salary",
      validate: ->(response, expected) {
        return { score: 0, max: 1 } unless response.is_a?(Hash)
        actual = (response["category"] || response["name"] || response.values.first).to_s
        score = actual.downcase.include?(expected.downcase) ? 1 : 0
        { score: score, max: 1 }
      }
    },
    {
      name: "Categorization: healthcare",
      category: "Single Categorization",
      prompt: single_categorization_prompt(
        "expense", "DR MED MUELLER PRAXIS BASEL", 150.00,
        %w[Healthcare Shopping Other],
        few_shot_examples: [
          { description: "APOTHEKE ZUM ENGEL", category: "Healthcare" },
          { description: "MANOR AG BASEL", category: "Shopping" }
        ]
      ),
      expected: "Healthcare",
      validate: ->(response, expected) {
        return { score: 0, max: 1 } unless response.is_a?(Hash)
        actual = (response["category"] || response["name"] || response.values.first).to_s
        score = actual.downcase.include?(expected.downcase) ? 1 : 0
        { score: score, max: 1 }
      }
    },

    # -----------------------------------------------------------------------
    # MERCHANT EXTRACTION — CategoryPatternExtractionJob#extract_merchant_names
    # -----------------------------------------------------------------------
    {
      name: "Merchant Extraction: store numbers + locations",
      category: "Merchant Extraction",
      prompt: merchant_extraction_prompt([
        "MIGROS BASEL STEINENVORSTADT #1234",
        "COOP PRATTELN HAUPTSTR 56",
        "SHELL OIL 57442634829 ZURICH",
        "STARBUCKS STORE #56789 BERN",
        "ALDI SUISSE #789 LIESTAL AG"
      ]),
      expected: %w[MIGROS COOP SHELL STARBUCKS ALDI],
      validate: ->(response, expected) {
        merchants = LlmBenchmark.extract_merchants(response)
        score = 0
        expected.each_with_index do |keyword, idx|
          next unless merchants[idx]
          score += 1 if merchants[idx].upcase.include?(keyword)
        end
        { score: score, max: expected.length }
      }
    },
    {
      name: "Merchant Extraction: reference codes + dates",
      category: "Merchant Extraction",
      prompt: merchant_extraction_prompt([
        "NETFLIX SARL LU REF:8827364 15.01.2025",
        "SBB MOBILE TICKET 2025-01-23 #44821",
        "AMAZON EU SARL*ABCDE12F MARKETPLACE",
        "SPOTIFY USA 9.99 USD MONTHLY"
      ]),
      expected: %w[NETFLIX SBB AMAZON SPOTIFY],
      validate: ->(response, expected) {
        merchants = LlmBenchmark.extract_merchants(response)
        score = 0
        expected.each_with_index do |keyword, idx|
          next unless merchants[idx]
          score += 1 if merchants[idx].upcase.include?(keyword)
        end
        { score: score, max: expected.length }
      }
    },
    {
      name: "Merchant Extraction: payment processors",
      category: "Merchant Extraction",
      prompt: merchant_extraction_prompt([
        "SQ *CORNER CAFE PORTLAND OR",
        "TST* SUSHI HOUSE SAN FRANCISCO",
        "GRUBHUB*THAI KITCHEN ORDER",
        "PP*EBAY MARKETPLACE PURCHASE",
        "DOORDASH*PIZZAHUT DELIVERY"
      ]),
      expected: %w[CORNER SUSHI THAI EBAY PIZZAHUT],
      validate: ->(response, expected) {
        merchants = LlmBenchmark.extract_merchants(response)
        score = 0
        expected.each_with_index do |keyword, idx|
          next unless merchants[idx]
          # For payment processor prefixes, the model should extract the actual merchant
          score += 1 if merchants[idx].upcase.include?(keyword)
        end
        { score: score, max: expected.length }
      }
    }
  ].freeze

  attr_reader :models

  def initialize(models: nil)
    @models = models || DEFAULT_MODELS
    @ollama_host = Rails.application.config.ollama.host
  end

  def run
    puts "=" * 70
    puts "Ollama LLM Model Benchmark"
    puts "=" * 70
    puts
    puts "Results saved to: #{RESULTS_FILE}"
    puts

    unless ollama_available?
      puts "ERROR: Ollama is not available at #{@ollama_host}"
      return nil
    end

    available = @models.select { |m| model_available?(m) }
    missing = @models - available

    if missing.any?
      puts "Missing models (run 'ollama pull <model>' to install):"
      missing.each { |m| puts "  - #{m}" }
      puts
    end

    if available.empty?
      puts "ERROR: No requested models available. Install at least one:"
      @models.each { |m| puts "  ollama pull #{m}" }
      return nil
    end

    results = load_results
    cached = results.keys & available
    if cached.any?
      puts "Cached results for: #{cached.join(', ')} (delete #{RESULTS_FILE} to reset)"
      puts
    end

    puts "Testing models: #{available.join(', ')}"
    puts "Running #{TEST_CASES.length} test cases per model..."
    puts
    puts "Test cases:"
    TEST_CASES.each_with_index { |t, i| puts "  #{i + 1}. #{t[:name]}" }
    puts

    available.each_with_index do |model, model_idx|
      if results[model]
        puts "-" * 70
        puts "Model: #{model} [#{model_idx + 1}/#{available.length}] (CACHED)"
        puts "-" * 70
        puts
        next
      end

      puts "-" * 70
      puts "Model: #{model} [#{model_idx + 1}/#{available.length}]"
      puts "-" * 70

      results[model] = { "total_score" => 0, "max_score" => 0, "total_time" => 0, "tests" => [] }

      TEST_CASES.each_with_index do |test, test_idx|
        print "  [#{test_idx + 1}/#{TEST_CASES.length}] #{test[:name]}... "
        $stdout.flush

        result = generate(model, test[:prompt], format: "json")

        if result[:success] && result[:response]
          validation = test[:validate].call(result[:response], test[:expected])
          results[model]["total_score"] += validation[:score]
          results[model]["max_score"] += validation[:max]
          results[model]["total_time"] += result[:time]
          results[model]["tests"] << {
            "name" => test[:name],
            "category" => test[:category],
            "score" => validation[:score],
            "max" => validation[:max],
            "time" => result[:time]
          }

          pct = (validation[:score].to_f / validation[:max] * 100).round(0)
          puts "#{validation[:score]}/#{validation[:max]} (#{pct}%) in #{result[:time].round(1)}s"
        else
          max_for_test = test[:validate].call({}, test[:expected])[:max]
          results[model]["max_score"] += max_for_test
          results[model]["tests"] << {
            "name" => test[:name],
            "category" => test[:category],
            "score" => 0,
            "max" => max_for_test,
            "error" => result[:error],
            "time" => result[:time]
          }
          puts "FAILED: #{result[:error]} (#{result[:time].round(1)}s)"
        end
      end

      save_results(results)
      pct = (results[model]["total_score"].to_f / results[model]["max_score"] * 100).round(1)
      puts "  -> Saved. Score: #{results[model]["total_score"]}/#{results[model]["max_score"]} (#{pct}%)"
      puts
    end

    results
  end

  def report(results)
    return unless results

    puts
    puts "=" * 70
    puts "SUMMARY"
    puts "=" * 70
    puts
    puts format("%-25s %10s %10s %10s", "Model", "Score", "Accuracy", "Avg Time")
    puts "-" * 55

    results.sort_by { |_, r| -(r["total_score"].to_f) }.each do |model, r|
      next unless r["max_score"]&.positive?
      pct = (r["total_score"].to_f / r["max_score"] * 100).round(1)
      avg_time = r["tests"].any? ? (r["total_time"] / r["tests"].length).round(1) : 0
      puts format("%-25s %7.1f/%-2d %9.1f%% %9.1fs", model, r["total_score"], r["max_score"], pct, avg_time)
    end

    # Category breakdown
    categories = TEST_CASES.map { |t| t[:category] }.uniq

    puts
    puts "=" * 70
    puts "BREAKDOWN BY CATEGORY"
    puts "=" * 70

    categories.each do |cat_name|
      cat_tests = TEST_CASES.select { |t| t[:category] == cat_name }
      next if cat_tests.empty?

      puts
      puts "#{cat_name}:"
      puts format("  %-25s %10s", "Model", "Score")

      results.sort_by { |_, r| -(r["total_score"].to_f) }.each do |model, r|
        model_cat_tests = r["tests"].select { |t| t["category"] == cat_name }
        next if model_cat_tests.empty?

        cat_score = model_cat_tests.sum { |t| t["score"] }
        cat_max = model_cat_tests.sum { |t| t["max"] }
        pct = cat_max.positive? ? (cat_score.to_f / cat_max * 100).round(0) : 0
        puts format("  %-25s %5.1f/%-2d (%d%%)", model, cat_score, cat_max, pct)
      end
    end

    # Recommendation
    puts
    puts "=" * 70
    puts "RECOMMENDATION"
    puts "=" * 70

    best = results.max_by { |_, r| r["max_score"]&.positive? ? r["total_score"].to_f / r["max_score"] : 0 }
    fastest = results.min_by { |_, r| r["tests"].any? ? r["total_time"] / r["tests"].length : Float::INFINITY }

    if best && fastest
      if best[0] == fastest[0]
        puts "  #{best[0]} is both most accurate and fastest — clear winner!"
      else
        best_pct = (best[1]["total_score"].to_f / best[1]["max_score"] * 100).round(1)
        fast_pct = (fastest[1]["total_score"].to_f / fastest[1]["max_score"] * 100).round(1)
        fast_avg = (fastest[1]["total_time"] / fastest[1]["tests"].length).round(1)

        puts "  Most accurate: #{best[0]} (#{best_pct}%)"
        puts "  Fastest: #{fastest[0]} (#{fast_avg}s avg, #{fast_pct}% accuracy)"

        if best_pct - fast_pct < 5 && fastest[0] != best[0]
          puts "  -> #{fastest[0]} is a viable alternative (similar accuracy, faster)"
        end
      end
    end

    puts
    puts "  Update config/initializers/ollama.rb with your chosen model:"
    puts "    config.model = ENV.fetch(\"OLLAMA_MODEL\", \"#{best&.first || 'llama3.1:8b'}\")"
    puts
  end

  private

  def ollama_available?
    response = HTTParty.get("#{@ollama_host}/api/tags", timeout: 5)
    response.success?
  rescue StandardError
    false
  end

  def model_available?(model)
    response = HTTParty.get("#{@ollama_host}/api/tags", timeout: 5)
    return false unless response.success?

    models = response.parsed_response["models"] || []
    model_base = model.split(":").first
    models.any? { |m| m["name"]&.start_with?(model_base) }
  rescue StandardError
    false
  end

  def generate(model, prompt, format: "json")
    start_time = Time.now

    body = { model: model, prompt: prompt, stream: false }
    body[:format] = format if format

    response = HTTParty.post(
      "#{@ollama_host}/api/generate",
      body: body.to_json,
      headers: { "Content-Type" => "application/json" },
      timeout: 300
    )

    elapsed = Time.now - start_time

    if response.success?
      text = response.parsed_response["response"]
      if format == "json"
        parsed = JSON.parse(text) rescue nil
        { success: true, response: parsed, raw: text, time: elapsed }
      else
        { success: true, response: text, raw: text, time: elapsed }
      end
    else
      { success: false, error: "API error: #{response.code}", time: elapsed }
    end
  rescue JSON::ParserError => e
    { success: false, error: "JSON parse error: #{e.message}", time: Time.now - start_time }
  rescue StandardError => e
    { success: false, error: e.message, time: Time.now - start_time }
  end

  def load_results
    return {} unless File.exist?(RESULTS_FILE)
    JSON.parse(File.read(RESULTS_FILE))
  rescue JSON::ParserError
    {}
  end

  def save_results(results)
    FileUtils.mkdir_p(File.dirname(RESULTS_FILE))
    File.write(RESULTS_FILE, JSON.pretty_generate(results))
  end
end

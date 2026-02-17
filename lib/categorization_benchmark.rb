# Repeatable benchmark for categorization pipeline accuracy.
# Tests all 3 phases independently and as a full pipeline.
# Designed to be re-run after embedding model changes to detect regressions.
#
# Requires Ollama with embedding + chat models available.
# NOT part of `rails test` — run via: rake categorization:benchmark
#
# How it works:
#   1. Seeds temporary "training" transactions (categorized, with embeddings)
#      to simulate real user history — required for Phase 2/3 to work.
#   2. Phase 1: tests pattern matching with descriptions containing seed patterns.
#   3. Phase 2/3: tests embedding similarity + LLM with merchant strings that
#      patterns won't catch (relies on training transaction embeddings).
#   4. Cleans up all temporary data after running.
class CategorizationBenchmark
  THRESHOLDS = {
    phase_1: 0.95,
    phase_2_3: 0.70,
    overall: 0.80
  }.freeze

  # Training transactions — seeded before benchmark to simulate user history.
  # These are different merchants than the test cases but in the same categories.
  # The pipeline learns from these via transaction-level embeddings (Phase 2).
  TRAINING_TRANSACTIONS = {
    "Groceries" => [
      "ALBERTSONS #789 BOISE ID",
      "FOOD LION #456 RALEIGH NC",
      "SHOPRITE #123 NEWARK NJ",
      "MEIJER #890 GRAND RAPIDS MI",
      "FOOD 4 LESS #567 LA CA"
    ],
    "Dining" => [
      "WENDYS #1234 DRIVE THRU",
      "SUBWAY #5678 DOWNTOWN",
      "TACO BELL #9012 AUSTIN TX",
      "CHICK-FIL-A #3456 ATLANTA",
      "PANDA EXPRESS #7890 SF CA"
    ],
    "Transportation" => [
      "YELLOW CAB SF RIDE",
      "SCOOT SHARE RENTAL SF",
      "ZIPCAR MEMBERSHIP MONTHLY",
      "BART TRANSIT CLIPPER"
    ],
    "Gas" => [
      "VALERO #1234 HOUSTON TX",
      "CASEY GEN STORE #567 IA",
      "PILOT TRAVEL CTR #890 TN",
      "QT QUIKTRIP #2345 OK"
    ],
    "Subscriptions" => [
      "MICROSOFT 365 MONTHLY",
      "SLACK TECHNOLOGIES INC",
      "NOTION LABS INC PLAN",
      "GITHUB INC SUBSCRIPTION"
    ],
    "Healthcare" => [
      "RITE AID PHARM #1234",
      "LABCORP #5678 BLOOD WORK",
      "OPTUM HEALTH PAYMENT",
      "ZOCDOC COPAY DR JONES"
    ],
    "Utilities" => [
      "SPECTRUM CABLE INTERNET",
      "XFINITY MOBILE PAYMENT",
      "DUKE ENERGY ELECTRIC",
      "SPRINT WIRELESS AUTOPAY"
    ],
    "Entertainment" => [
      "CINEMARK THEATRES #123",
      "EVENTBRITE ORDER #456",
      "BOWLERO LANES #789",
      "IMAX THEATRE TICKETS"
    ],
    "Travel" => [
      "AMERICAN AIR #1234 DFW",
      "HYATT HOTEL CHICAGO IL",
      "HERTZ RENT-A-CAR #567",
      "BOOKING.COM RESERVATION"
    ],
    "Insurance" => [
      "LIBERTY MUTUAL AUTOPAY",
      "FARMERS INS GROUP PREM",
      "ERIE INSURANCE PAYMENT",
      "TRAVLERS INS QUARTERLY"
    ]
  }.freeze

  # Phase 1: descriptions that MUST contain a seed pattern substring.
  # Phase 2/3: realistic merchant strings that patterns won't match.
  #
  # IMPORTANT: Phase 2/3 descriptions must NOT contain any seed pattern
  # substring from ANY category. Check against db/seeds.rb when editing.
  # Common false-positive risks: "uber", "bp", "apple", "gap", "spa", "tax"
  SYNTHETIC_TRANSACTIONS = {
    "Groceries" => {
      phase_1: [
        "WHOLE FOODS MKT #1234 SEATTLE WA",
        "TRADER JOE'S #567 PORTLAND OR",
        "SAFEWAY STORE #890 SAN FRANCISCO",
        "KROGER #4521 COLUMBUS OH",
        "WALMART SUPERCENTER #123 AUSTIN TX",
        "COSTCO WHSE #1234 SEATTLE WA",
        "ALDI FOODS #789 CHICAGO IL"
      ],
      phase_2_3: [
        "SPROUTS FARMERS MKT #45",
        "H-E-B #321",
        "PUBLIX SUPER MARKETS INC",
        "PIGGLY WIGGLY #12",
        "WEGMANS FOOD MKTS #88",
        "WINCO FOODS #234"
      ]
    },
    "Dining" => {
      phase_1: [
        "GRUBHUB*THAI KITCHEN ORDER",
        "DOORDASH*PIZZAHUT",
        "UBEREATS*MCDONALDS ORDER",
        "DINNER AT THE LOCAL BISTRO",
        "SQ *CORNER CAFE PORTLAND"
      ],
      phase_2_3: [
        "MCDONALDS F1234",
        "STARBUCKS STORE #56789",
        "CHIPOTLE ONLINE ORDER",
        "PANERA BREAD #4567",
        "TST* SUSHI PLACE",
        "SQ *TAQUERIA EL SOL"
      ]
    },
    "Transportation" => {
      phase_1: [
        "UBER TRIP HELP.UBER.COM",
        "LYFT *RIDE 12345",
        "METRO TRANSIT AUTHORITY",
        "PARKING GARAGE SF DOWNTOWN",
        "TOLL CHARGE I-95 EZPASS"
      ],
      phase_2_3: [
        "CITIBIKE MEMBERSHIP",
        "BIRD SCOOTER SHARE",
        "LIMEBIKE RIDE SF"
      ]
    },
    "Gas" => {
      phase_1: [
        "SHELL OIL 57442634829",
        "CHEVRON STN 1234 SEATTLE",
        "EXXONMOBIL #5678",
        "BP #8765432 PORTLAND OR",
        "ARCO AMPM #4321 LA CA"
      ],
      phase_2_3: [
        "MARATHON PETRO 5678",
        "SUNOCO #1234 NJ",
        "WAWA #567 PHILLY PA"
      ]
    },
    "Subscriptions" => {
      phase_1: [
        "NETFLIX.COM MONTHLY",
        "SPOTIFY USA ACCT",
        "HULU *MONTHLY PLAN",
        "AMAZON PRIME MEMBERSHIP",
        "YOUTUBE MONTHLY PLAN"
      ],
      phase_2_3: [
        "CHATGPT PLUS OPENAI",
        "DROPBOX PLUS ANNUAL",
        "ADOBE CREATIVE CLOUD"
      ]
    },
    "Healthcare" => {
      phase_1: [
        "CVS/PHARMACY #1234 SEATTLE",
        "WALGREENS #5678 PORTLAND",
        "DR SMITH MEDICAL GROUP",
        "CITY HOSPITAL COPAY"
      ],
      phase_2_3: [
        "KAISER PERMANENTE BILL",
        "QUEST DIAGNOSTICS LAB",
        "LENSCRAFTERS #789"
      ]
    },
    "Utilities" => {
      phase_1: [
        "PGE ELECTRIC BILL PYMNT",
        "CITY WATER BILL QUARTERLY",
        "NW NATURAL GAS BILL PYMNT"
      ],
      phase_2_3: [
        "AT&T WRLS PYMNT",
        "COMCAST CABLE INTERNET",
        "VERIZON WRLS PAY",
        "T-MOBL AUTOPAY"
      ]
    },
    "Entertainment" => {
      phase_1: [
        "AMC MOVIE THEATRES #1234",
        "REGAL CINEMAS #567",
        "MUSEUM OF MODERN ART ADM",
        "LIVE CONCERT NATION #89"
      ],
      phase_2_3: [
        "STUBHUB INC PURCHASE",
        "FANDANGO ORDER #456",
        "TOPGOLF #1234 DALLAS"
      ]
    },
    "Travel" => {
      phase_1: [
        "UNITED AIRLINES FLIGHT",
        "MARRIOTT HOTEL STAY",
        "AIRBNB *HMXYZ123",
        "DELTA AIR LINES FLT"
      ],
      phase_2_3: [
        "SOUTHWEST WN #1234",
        "HILTON HHONORS RSRV",
        "VRBO STAY PYMNT"
      ]
    },
    "Insurance" => {
      phase_1: [
        "GEICO AUTO PYMNT",
        "STATE FARM MONTHLY",
        "ALLSTATE AUTOPAY",
        "PROGRESSIVE CORP PYMNT",
        "HOME INSURANCE PREM"
      ],
      phase_2_3: [
        "USAA AUTO PYMNT",
        "LEMONADE INC RENTERS",
        "NATIONWIDE MUTUAL"
      ]
    }
  }.freeze

  def run
    setup_benchmark_data!

    results = {
      phase_1: { correct: 0, total: 0, details: [] },
      phase_2_3: { correct: 0, total: 0, details: [] },
      overall: { correct: 0, total: 0 }
    }

    begin
      SYNTHETIC_TRANSACTIONS.each do |category_name, phases|
        # Phase 1: pattern matching only (call find_by_pattern directly)
        phases[:phase_1].each do |desc|
          matched = Category.find_by_pattern(desc, "expense")
          correct = matched&.name == category_name
          results[:phase_1][:total] += 1
          results[:phase_1][:correct] += 1 if correct
          results[:overall][:total] += 1
          results[:overall][:correct] += 1 if correct
          unless correct
            results[:phase_1][:details] << { expected: category_name, description: desc, got: matched&.name }
          end
        end

        # Phase 2/3: full pipeline (should NOT match Phase 1 patterns)
        phases[:phase_2_3].each do |desc|
          txn = { description: desc, transaction_type: "expense", amount: 50.00,
                  category_id: nil, category_name: nil, matched_phase: nil }
          service = CategoryMatchingService.new([ txn ])
          service.categorize
          correct = txn[:category_name] == category_name
          results[:phase_2_3][:total] += 1
          results[:phase_2_3][:correct] += 1 if correct
          results[:overall][:total] += 1
          results[:overall][:correct] += 1 if correct
          unless correct
            results[:phase_2_3][:details] << {
              expected: category_name, description: desc,
              got: txn[:category_name], phase: txn[:matched_phase]
            }
          end
        end
      end
    ensure
      teardown_benchmark_data!
    end

    results[:all_passed] = THRESHOLDS.all? do |phase, threshold|
      data = results[phase]
      next true if data.nil? || data[:total].zero?
      (data[:correct].to_f / data[:total]) >= threshold
    end

    results
  end

  def report(results)
    puts ""
    puts "== Categorization Pipeline Benchmark =="
    puts "Test transactions: #{results[:overall][:total]}"
    puts ""

    [ :phase_1, :phase_2_3, :overall ].each do |phase|
      data = results[phase]
      next if data[:total].zero?

      pct = (data[:correct].to_f / data[:total] * 100).round(0)
      threshold = (THRESHOLDS[phase] * 100).round(0) if THRESHOLDS[phase]
      status = threshold ? (pct >= threshold ? "PASS" : "FAIL") : ""
      threshold_str = threshold ? " (threshold: #{threshold}%)" : ""
      label = {
        phase_1: "Phase 1 (Pattern Matching)",
        phase_2_3: "Phase 2/3 (Embeddings + LLM)",
        overall: "Overall Pipeline"
      }[phase]
      puts "#{label}: #{data[:correct]}/#{data[:total]} (#{pct}%) #{status}#{threshold_str}"
    end

    # Detail misses
    [ :phase_1, :phase_2_3 ].each do |phase|
      details = results[phase][:details]
      next if details.empty?

      puts ""
      label = phase == :phase_1 ? "Phase 1" : "Phase 2/3"
      puts "#{label} misses:"
      details.each do |d|
        phase_info = d[:phase] ? " [matched phase #{d[:phase]}]" : ""
        puts "  #{d[:expected]}: \"#{d[:description]}\" -> #{d[:got] || 'nil'}#{phase_info}"
      end
    end

    puts ""
    puts "Result: #{results[:all_passed] ? 'ALL PASSED' : 'SOME FAILED'}"
  end

  private

  # Set up benchmark data: category embeddings + training transactions with embeddings
  def setup_benchmark_data!
    ensure_category_embeddings!
    seed_training_transactions!
  end

  # Clean up: remove training transactions created by the benchmark
  def teardown_benchmark_data!
    count = Transaction.where(description: "BENCHMARK_TRAINING").count
    Transaction.where(description: "BENCHMARK_TRAINING").delete_all
    puts "Cleaned up #{count} training transactions." if count > 0
  end

  # Ensure category embeddings exist before benchmarking.
  def ensure_category_embeddings!
    missing = Category.where(embedding: nil).count
    return if missing.zero?

    puts "Computing embeddings for #{missing} categories..."
    Category.where(embedding: nil).find_each do |cat|
      vector = OllamaService.embed(cat.embedding_text)
      cat.update_column(:embedding, vector.pack("f*"))
    rescue OllamaService::Error => e
      puts "  Warning: Failed to embed '#{cat.name}': #{e.message}"
    end
    puts "Done."
  end

  # Create training transactions with embeddings to simulate user history.
  # These enable transaction-level nearest-neighbor search (Phase 2a).
  def seed_training_transactions!
    account = Account.first
    unless account
      puts "Warning: No accounts found. Create at least one account before running benchmark."
      return
    end

    total = TRAINING_TRANSACTIONS.values.flatten.size
    puts "Seeding #{total} training transactions with embeddings..."

    created = 0
    TRAINING_TRANSACTIONS.each do |category_name, descriptions|
      category = Category.find_by(name: category_name, category_type: "expense")
      unless category
        puts "  Warning: Category '#{category_name}' not found, skipping"
        next
      end

      descriptions.each do |desc|
        vector = OllamaService.embed(desc)
        Transaction.create!(
          account: account,
          category: category,
          description: "BENCHMARK_TRAINING",
          amount: 50.00,
          transaction_type: "expense",
          date: Date.current,
          embedding: vector.pack("f*")
        )
        created += 1
        print "\r  #{created}/#{total} embedded..."
      rescue OllamaService::Error => e
        puts "\n  Warning: Failed to embed '#{desc}': #{e.message}"
      end
    end
    puts "\r  #{created}/#{total} training transactions seeded."
  end
end

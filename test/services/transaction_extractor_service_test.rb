require "test_helper"

class TransactionExtractorServiceTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:checking_account)
    @text = "Statement\n2026-01-15 COFFEE SHOP 5.50\n2026-01-16 SALARY DEPOSIT 2000.00"
  end

  # ========================================
  # Initialization tests
  # ========================================

  test "initializes with text and account (backward compatibility)" do
    extractor = TransactionExtractorService.new(@text, @account)

    assert_equal @text, extractor.text
    assert_equal [ @text ], extractor.chunks
    assert_equal @account, extractor.account
  end

  test "initializes with array of chunks" do
    chunks = [ "Page 1 content", "Page 2 content" ]
    extractor = TransactionExtractorService.new(chunks, @account)

    assert_equal chunks, extractor.chunks
    assert_equal @account, extractor.account
    assert_equal "Page 1 content", extractor.text # First chunk for backward compat
  end

  test "error classes are defined" do
    assert_kind_of Class, TransactionExtractorService::Error
    assert_kind_of Class, TransactionExtractorService::ExtractionError
    assert TransactionExtractorService::ExtractionError < TransactionExtractorService::Error
  end

  test "initializes with file_type option" do
    extractor = TransactionExtractorService.new(@text, @account, file_type: :csv)

    assert extractor.csv?
    refute extractor.pdf?
  end

  test "defaults to pdf file type" do
    extractor = TransactionExtractorService.new(@text, @account)

    assert extractor.pdf?
    refute extractor.csv?
  end

  test "initializes with on_progress callback" do
    progress_calls = []
    callback = ->(current, total, **kwargs) { progress_calls << [ current, total, kwargs ] }

    extractor = TransactionExtractorService.new(@text, @account, on_progress: callback)

    assert_equal callback, extractor.on_progress
  end

  # ========================================
  # Response parsing tests
  # ========================================

  test "parse_response handles hash with transactions key" do
    extractor = TransactionExtractorService.new(@text, @account)
    response = { "transactions" => [ { "date" => "2026-01-15", "description" => "Test", "amount" => 10 } ] }

    result = extractor.send(:parse_response, response)

    assert_equal 1, result.length
    assert_equal "2026-01-15", result.first["date"]
  end

  test "parse_response handles hash with data key" do
    extractor = TransactionExtractorService.new(@text, @account)
    response = { "data" => [ { "date" => "2026-01-15", "description" => "Test", "amount" => 10 } ] }

    result = extractor.send(:parse_response, response)

    assert_equal 1, result.length
  end

  test "parse_response handles hash with results key" do
    extractor = TransactionExtractorService.new(@text, @account)
    response = { "results" => [ { "date" => "2026-01-15", "description" => "Test", "amount" => 10 } ] }

    result = extractor.send(:parse_response, response)

    assert_equal 1, result.length
  end

  test "parse_response handles array directly" do
    extractor = TransactionExtractorService.new(@text, @account)
    response = [ { "date" => "2026-01-15", "description" => "Test", "amount" => 10 } ]

    result = extractor.send(:parse_response, response)

    assert_equal 1, result.length
  end

  test "parse_response raises error for invalid response type" do
    extractor = TransactionExtractorService.new(@text, @account)

    error = assert_raises(TransactionExtractorService::ExtractionError) do
      extractor.send(:parse_response, "invalid string")
    end
    assert_match(/Invalid response format/, error.message)
  end

  test "parse_response raises error when transactions is not an array" do
    extractor = TransactionExtractorService.new(@text, @account)
    response = { "transactions" => "not an array" }

    error = assert_raises(TransactionExtractorService::ExtractionError) do
      extractor.send(:parse_response, response)
    end
    assert_match(/expected 'transactions' array/, error.message)
  end

  # ========================================
  # Category response parsing tests
  # ========================================

  test "parse_categories_response handles array of strings" do
    extractor = TransactionExtractorService.new(@text, @account)
    response = [ "groceries", "entertainment", "salary" ]

    result = extractor.send(:parse_categories_response, response)

    assert_equal [ "groceries", "entertainment", "salary" ], result
  end

  test "parse_categories_response handles hash with categories key" do
    extractor = TransactionExtractorService.new(@text, @account)
    response = { "categories" => [ "groceries", "entertainment" ] }

    result = extractor.send(:parse_categories_response, response)

    assert_equal [ "groceries", "entertainment" ], result
  end

  test "parse_categories_response handles hash with transactions key" do
    extractor = TransactionExtractorService.new(@text, @account)
    response = { "transactions" => [ "groceries", "entertainment" ] }

    result = extractor.send(:parse_categories_response, response)

    assert_equal [ "groceries", "entertainment" ], result
  end

  test "parse_categories_response handles single string response" do
    extractor = TransactionExtractorService.new(@text, @account)

    result = extractor.send(:parse_categories_response, "groceries")

    assert_equal [ "groceries" ], result
  end

  test "parse_categories_response handles empty response" do
    extractor = TransactionExtractorService.new(@text, @account)

    result = extractor.send(:parse_categories_response, nil)

    assert_equal [], result
  end

  # ========================================
  # Field normalization tests
  # ========================================

  test "normalize_field_names maps alternative field names" do
    extractor = TransactionExtractorService.new(@text, @account)

    txn = {
      "transaction_date" => "2026-01-15",
      "merchant" => "Coffee Shop",
      "value" => 5.50,
      "transaction_type" => "expense"
    }

    result = extractor.send(:normalize_field_names, txn)

    assert_equal "2026-01-15", result["date"]
    assert_equal "Coffee Shop", result["description"]
    assert_equal 5.50, result["amount"]
    assert_equal "expense", result["type"]
  end

  test "normalize_field_names handles credit/debit fields for type inference" do
    extractor = TransactionExtractorService.new(@text, @account)

    credit_txn = { "date" => "2026-01-15", "description" => "Deposit", "credit" => 100 }
    result = extractor.send(:normalize_field_names, credit_txn)
    assert_equal "income", result["type"]

    debit_txn = { "date" => "2026-01-15", "description" => "Purchase", "debit" => 50 }
    result = extractor.send(:normalize_field_names, debit_txn)
    assert_equal "expense", result["type"]
  end

  # ========================================
  # Transaction validation tests
  # ========================================

  test "valid_transaction returns true for complete transaction" do
    extractor = TransactionExtractorService.new(@text, @account)
    txn = { "date" => "2026-01-15", "description" => "Test", "amount" => 10 }

    assert extractor.send(:valid_transaction?, txn)
  end

  test "valid_transaction returns false when date is missing" do
    extractor = TransactionExtractorService.new(@text, @account)
    txn = { "description" => "Test", "amount" => 10 }

    refute extractor.send(:valid_transaction?, txn)
  end

  test "valid_transaction returns false when description is missing" do
    extractor = TransactionExtractorService.new(@text, @account)
    txn = { "date" => "2026-01-15", "amount" => 10 }

    refute extractor.send(:valid_transaction?, txn)
  end

  test "valid_transaction returns false when amount is missing" do
    extractor = TransactionExtractorService.new(@text, @account)
    txn = { "date" => "2026-01-15", "description" => "Test" }

    refute extractor.send(:valid_transaction?, txn)
  end

  # ========================================
  # Transaction normalization tests
  # ========================================

  test "normalize_transaction creates proper hash structure" do
    extractor = TransactionExtractorService.new(@text, @account)
    txn = {
      "date" => "2026-01-15",
      "description" => "  Coffee Shop  ",
      "amount" => -5.50,
      "type" => "expense"
    }

    result = extractor.send(:normalize_transaction, txn)

    assert_equal Date.new(2026, 1, 15), result[:date]
    assert_equal "Coffee Shop", result[:description]
    assert_equal 5.50, result[:amount]  # Should be absolute value
    assert_equal "expense", result[:transaction_type]
    assert_nil result[:category_id]
    assert_nil result[:category_name]
    assert_equal @account.id, result[:account_id]
  end

  test "normalize_transaction defaults to expense type" do
    extractor = TransactionExtractorService.new(@text, @account)
    txn = { "date" => "2026-01-15", "description" => "Test", "amount" => 10, "type" => "unknown" }

    result = extractor.send(:normalize_transaction, txn)

    assert_equal "expense", result[:transaction_type]
  end

  test "normalize_transaction handles income type" do
    extractor = TransactionExtractorService.new(@text, @account)
    txn = { "date" => "2026-01-15", "description" => "Salary", "amount" => 2000, "type" => "income" }

    result = extractor.send(:normalize_transaction, txn)

    assert_equal "income", result[:transaction_type]
  end

  test "normalize_transaction returns nil for invalid date" do
    extractor = TransactionExtractorService.new(@text, @account)
    txn = { "date" => "invalid-date", "description" => "Test", "amount" => 10 }

    result = extractor.send(:normalize_transaction, txn)

    assert_nil result
  end

  # ========================================
  # Date parsing tests
  # ========================================

  test "parse_date handles ISO format" do
    extractor = TransactionExtractorService.new(@text, @account, file_type: :csv)

    result = extractor.send(:parse_date, "2026-01-15")

    assert_equal Date.new(2026, 1, 15), result
  end

  test "parse_date handles European format" do
    extractor = TransactionExtractorService.new(@text, @account, file_type: :csv)

    result = extractor.send(:parse_date, "15.01.2026")

    assert_equal Date.new(2026, 1, 15), result
  end

  test "parse_date returns nil for invalid date" do
    extractor = TransactionExtractorService.new(@text, @account, file_type: :csv)

    result = extractor.send(:parse_date, "not-a-date")

    assert_nil result
  end

  # ========================================
  # Statement period extraction tests
  # ========================================

  test "extract_statement_period parses date range" do
    text = "Statement period: 01.01.2026 - 31.01.2026"
    extractor = TransactionExtractorService.new(text, @account)

    result = extractor.send(:extract_statement_period, text)

    assert_kind_of Range, result
    assert_equal Date.new(2026, 1, 1), result.begin
    assert_equal Date.new(2026, 1, 31), result.end
  end

  test "extract_statement_period handles 'bis' separator" do
    text = "Auszug vom 01.12.2025 bis 31.12.2025"
    extractor = TransactionExtractorService.new(text, @account)

    result = extractor.send(:extract_statement_period, text)

    assert_kind_of Range, result
    assert_equal Date.new(2025, 12, 1), result.begin
    assert_equal Date.new(2025, 12, 31), result.end
  end

  test "extract_statement_period handles ISO date range format" do
    text = "Statement period from 2026-01-01 to 2026-01-31"
    extractor = TransactionExtractorService.new(text, @account)

    result = extractor.send(:extract_statement_period, text)

    assert_kind_of Range, result
    assert_equal Date.new(2026, 1, 1), result.begin
    assert_equal Date.new(2026, 1, 31), result.end
  end

  test "extract_statement_period handles Abrechnung format" do
    text = "Abrechnung vom 31.01.2026"
    extractor = TransactionExtractorService.new(text, @account)

    result = extractor.send(:extract_statement_period, text)

    assert_kind_of Range, result
    assert_equal Date.new(2026, 1, 1), result.begin
    assert_equal Date.new(2026, 1, 31), result.end
  end

  test "extract_statement_period returns nil for blank text" do
    extractor = TransactionExtractorService.new(@text, @account)

    result = extractor.send(:extract_statement_period, "")

    assert_nil result
  end

  test "extract_statement_period returns nil when no period found" do
    text = "Just some random text without dates"
    extractor = TransactionExtractorService.new(text, @account)

    result = extractor.send(:extract_statement_period, text)

    assert_nil result
  end

  # ========================================
  # Category finding tests
  # ========================================

  test "find_category finds exact match" do
    extractor = TransactionExtractorService.new(@text, @account)

    result = extractor.send(:find_category, "groceries", "expense")

    assert_equal categories(:groceries), result
  end

  test "find_category finds case-insensitive match" do
    extractor = TransactionExtractorService.new(@text, @account)

    result = extractor.send(:find_category, "GROCERIES", "expense")

    assert_equal categories(:groceries), result
  end

  test "find_category returns nil for blank name" do
    extractor = TransactionExtractorService.new(@text, @account)

    result = extractor.send(:find_category, "", "expense")

    assert_nil result
  end

  test "find_category returns nil for nil name" do
    extractor = TransactionExtractorService.new(@text, @account)

    result = extractor.send(:find_category, nil, "expense")

    assert_nil result
  end

  test "find_category respects category type" do
    extractor = TransactionExtractorService.new(@text, @account)

    # groceries is an expense category
    result = extractor.send(:find_category, "groceries", "income")

    assert_nil result
  end

  # ========================================
  # Prompt building tests
  # ========================================

  test "build_extraction_prompt uses CSV prompt for CSV files" do
    extractor = TransactionExtractorService.new("header\nrow1", @account, file_type: :csv)

    prompt = extractor.send(:build_extraction_prompt, "header\nrow1")

    assert_match(/Parse this CSV into JSON/, prompt)
    assert_match(/exactly 1 data rows/, prompt)
  end

  test "build_extraction_prompt uses PDF prompt for PDF files" do
    extractor = TransactionExtractorService.new(@text, @account, file_type: :pdf)

    prompt = extractor.send(:build_extraction_prompt, @text)

    assert_match(/financial transaction parser/, prompt)
    assert_match(/ACCOUNT CURRENCY:/, prompt)
  end

  test "build_pdf_extraction_prompt includes account currency" do
    extractor = TransactionExtractorService.new(@text, @account)

    prompt = extractor.send(:build_pdf_extraction_prompt, @text)

    assert_match(/ACCOUNT CURRENCY: USD/, prompt)
  end

  # ========================================
  # Extract method tests (requires OllamaService)
  # ========================================

  test "extract raises error when Ollama is not available" do
    extractor = TransactionExtractorService.new(@text, @account)

    OllamaService.define_singleton_method(:available?) { false }

    begin
      error = assert_raises(TransactionExtractorService::ExtractionError) do
        extractor.extract
      end
      assert_match(/Ollama is not available/, error.message)
    ensure
      OllamaService.define_singleton_method(:available?) do
        response = Net::HTTP.get_response(URI("#{base_url}/api/tags"))
        response.is_a?(Net::HTTPSuccess)
      rescue
        false
      end
    end
  end
end

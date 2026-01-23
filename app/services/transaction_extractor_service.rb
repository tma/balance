# Extracts transactions from PDF bank statements using LLM
# For CSV files, use CsvMappingAnalyzerService + DeterministicCsvParserService instead
class TransactionExtractorService
  class Error < StandardError; end
  class ExtractionError < Error; end

  CATEGORY_BATCH_SIZE = 10

  attr_reader :chunks, :account, :on_progress, :statement_period

  # Initialize with text chunks (PDF pages) and account
  # @param chunks [Array<String>, String] Text chunks to process
  # @param account [Account] The account for transactions
  # @param on_progress [Proc, nil] Optional callback called with (current_chunk, total_chunks)
  def initialize(chunks, account, on_progress: nil)
    @chunks = chunks.is_a?(Array) ? chunks : [ chunks ]
    @account = account
    @on_progress = on_progress
    @statement_period = extract_statement_period(@chunks.join("\n"))
    @extracted_count = 0
  end

  # Extract transactions from all chunks using Ollama
  # @return [Array<Hash>] Array of transaction hashes
  def extract
    unless OllamaService.available?
      raise ExtractionError, "Ollama is not available. Please ensure it is running."
    end

    all_transactions = extract_from_chunks
    categorize_transactions(all_transactions)
    all_transactions
  rescue OllamaService::Error => e
    raise ExtractionError, "Failed to extract transactions: #{e.message}"
  end

  # Categorize transactions using LLM (public so CSV imports can use it)
  # @param transactions [Array<Hash>] Array of transaction hashes with :description, :transaction_type
  def categorize_transactions(transactions)
    return if transactions.empty?

    @on_progress&.call(@chunks.size + 1, @chunks.size + 1, extracted_count: transactions.size, message: "Categorizing transactions")
    Rails.logger.info "Categorizing #{transactions.size} transactions"

    expense_categories = Category.expense
    income_categories = Category.income

    transactions.each_slice(CATEGORY_BATCH_SIZE) do |batch|
      categorize_batch(batch, expense_categories, income_categories)
    end
  end

  private

  def extract_from_chunks
    all_transactions = []
    total_steps = @chunks.size + 1

    @chunks.each_with_index do |chunk, index|
      current = index + 1
      Rails.logger.info "Extracting from chunk #{current}/#{@chunks.size}"
      @on_progress&.call(current, total_steps, extracted_count: @extracted_count, message: "Extracting transactions")

      prompt = build_extraction_prompt(chunk)
      response = OllamaService.generate_json(prompt)

      transactions = parse_response(response)
      normalized = validate_and_normalize(transactions)
      all_transactions.concat(normalized)
      @extracted_count += normalized.size
    end

    all_transactions
  end

  def categorize_batch(transactions, expense_categories, income_categories)
    prompt = build_categorization_prompt(transactions, expense_categories, income_categories)
    response = OllamaService.generate_json(prompt)
    categories = parse_categories_response(response)

    transactions.each_with_index do |txn, index|
      category_name = categories[index]
      next unless category_name

      category = find_category(category_name, txn[:transaction_type])
      txn[:category_id] = category&.id
      txn[:category_name] = category&.name || category_name
    end
  rescue OllamaService::Error => e
    Rails.logger.warn "Failed to categorize batch: #{e.message}"
  end

  def build_extraction_prompt(chunk_text)
    ignore_list = account.ignore_patterns_list.join(", ")

    <<~PROMPT
      You are a financial transaction parser. Extract all transactions from the following financial statement.

      ACCOUNT CURRENCY: #{account.currency}

      RULES:
      1. Extract EVERY transaction you can find
      2. Dates must be in YYYY-MM-DD format
      3. Amounts must be positive numbers with two decimal places (e.g., 123.45), no currency symbols
      4. Type: "expense" for money out, "income" for money in
      5. When both foreign currency and #{account.currency} amounts shown, use the #{account.currency} amount
      6. IGNORE lines containing: #{ignore_list}
      7. If multiple dates per line, use "Date"/"Datum", NOT "Valuta"/"Value Date"

      DATE FORMAT (CRITICAL):
      - European format: DD.MM.YY or DD.MM.YYYY (day FIRST, then month)
      - "07.11.25" → Day=07, Month=11 → "2025-11-07"
      - "23.01.25" → Day=23, Month=01 → "2025-01-23"
      - NEVER interpret first number as month
      - Two-digit year "25" means 2025
      - Get the year from document header/statement date

      OUTPUT FORMAT (JSON only):
      {
        "transactions": [
          {"date": "YYYY-MM-DD", "description": "merchant", "amount": 123.45, "type": "expense"}
        ]
      }

      Return {"transactions": []} if no transactions found.

      BANK STATEMENT:
      ---
      #{chunk_text.truncate(8000)}
      ---
    PROMPT
  end

  def build_categorization_prompt(transactions, expense_categories, income_categories)
    txn_list = transactions.map.with_index do |txn, i|
      "#{i + 1}. [#{txn[:transaction_type].upcase}] #{txn[:description]} (#{txn[:amount]})"
    end.join("\n")

    category_hints = build_category_hints(expense_categories, income_categories)
    expense_names = expense_categories.pluck(:name)
    income_names = income_categories.pluck(:name)

    <<~PROMPT
      Categorize these transactions. You MUST use ONLY the exact category names listed below.

      EXPENSE CATEGORIES: #{expense_names.join(", ")}
      INCOME CATEGORIES: #{income_names.join(", ")}
      #{category_hints}
      TRANSACTIONS:
      #{txn_list}

      RULES:
      - Use ONLY category names from the lists above (exact spelling)
      - For expenses, pick from EXPENSE CATEGORIES
      - For income, pick from INCOME CATEGORIES
      - If unsure, use "other expense" or "other income"

      OUTPUT: JSON array of category names, same order as transactions:
      ["category1", "category2", ...]
    PROMPT
  end

  def build_category_hints(expense_categories, income_categories)
    hints = []

    (expense_categories + income_categories).each do |category|
      next unless category.has_match_patterns?
      hints << "- #{category.name}: #{category.match_patterns_list.join(", ")}"
    end

    return "" if hints.empty?
    "\nCATEGORY HINTS (assign category if description contains these):\n#{hints.join("\n")}\n"
  end

  def parse_response(response)
    transactions = case response
    when Array
      response
    when Hash
      response["transactions"] || response["data"] || response["results"] || []
    else
      raise ExtractionError, "Invalid response format: expected Hash or Array, got #{response.class}"
    end

    unless transactions.is_a?(Array)
      raise ExtractionError, "Invalid response format: expected 'transactions' array, got #{transactions.class}"
    end

    transactions
  end

  def parse_categories_response(response)
    categories = case response
    when Array
      response
    when Hash
      if response["categories"].is_a?(Array)
        response["categories"]
      elsif response["transactions"].is_a?(Array)
        response["transactions"]
      elsif response.values.first.is_a?(Array)
        response.values.first
      else
        response.keys.sort.map { |k| response[k] }
      end
    when String
      [ response ]
    else
      []
    end

    Array(categories).map { |c| c.to_s.presence }
  end

  def validate_and_normalize(transactions)
    transactions.filter_map do |txn|
      txn = normalize_field_names(txn)

      unless valid_transaction?(txn)
        Rails.logger.warn "Skipping invalid transaction: #{txn.inspect}"
        next
      end

      unless valid_transaction_content?(txn)
        Rails.logger.info "Skipping non-transaction line: #{txn.inspect}"
        next
      end

      normalize_transaction(txn)
    end
  end

  def normalize_field_names(txn)
    {
      "date" => txn["date"] || txn["transaction_date"] || txn["Date"],
      "description" => txn["description"] || txn["name"] || txn["merchant"] || txn["Description"] || txn["memo"],
      "amount" => txn["amount"] || txn["value"] || txn["Amount"],
      "type" => txn["type"] || txn["transaction_type"] || txn["Type"]
    }
  end

  def valid_transaction?(txn)
    txn["date"].present? && txn["description"].present? && txn["amount"].present?
  end

  def valid_transaction_content?(txn)
    description = txn["description"].to_s.strip
    return false if description.blank?
    return false if account.should_ignore_for_import?(description)
    true
  end

  def normalize_transaction(txn)
    date = parse_date(txn["date"])
    return nil unless date

    type = txn["type"].to_s.downcase == "income" ? "income" : "expense"

    {
      date: date,
      description: txn["description"].to_s.strip,
      amount: txn["amount"].to_f.abs.round(2),
      transaction_type: type,
      category_id: nil,
      category_name: nil,
      account_id: account.id
    }
  end

  def parse_date(date_str)
    parsed = Date.parse(date_str.to_s)
    return parsed unless statement_period
    return parsed if statement_period.cover?(parsed)
    nil
  rescue ArgumentError
    nil
  end

  def find_category(name, type)
    return nil if name.blank?

    name_str = name.to_s.strip
    return nil if name_str.empty?

    category = Category.find_by(name: name_str, category_type: type)
    return category if category

    category = Category.where(category_type: type).where("LOWER(name) = ?", name_str.downcase).first
    return category if category

    Category.where(category_type: type).where("LOWER(name) LIKE ?", "%#{name_str.downcase}%").first
  end

  def extract_statement_period(text)
    return nil if text.blank?

    if (match = text.match(/(\d{1,2}\.\d{1,2}\.\d{2,4})\s*(?:-|to|bis|–)\s*(\d{1,2}\.\d{1,2}\.\d{2,4})/i))
      start_date = parse_statement_date(match[1])
      end_date = parse_statement_date(match[2])
      return build_statement_range(start_date, end_date)
    end

    if (match = text.match(/statement\s+period\D+(\d{4}-\d{2}-\d{2})\D+(\d{4}-\d{2}-\d{2})/i))
      start_date = parse_statement_date(match[1])
      end_date = parse_statement_date(match[2])
      return build_statement_range(start_date, end_date)
    end

    if (match = text.match(/abrechnung\s+vom\s+(\d{1,2}\.\d{1,2}\.\d{2,4})/i))
      end_date = parse_statement_date(match[1])
      return (end_date.beginning_of_month..end_date) if end_date
    end

    nil
  end

  def parse_statement_date(date_str)
    return nil if date_str.blank?

    cleaned = date_str.to_s.strip
    if cleaned.match?(/\A\d{1,2}\.\d{1,2}\.\d{2,4}\z/)
      day, month, year = cleaned.split(".")
      year = year.length == 2 ? "20#{year}" : year
      Date.new(year.to_i, month.to_i, day.to_i)
    else
      Date.parse(cleaned)
    end
  rescue ArgumentError
    nil
  end

  def build_statement_range(start_date, end_date)
    return nil unless start_date && end_date
    start_date, end_date = [ start_date, end_date ].minmax
    start_date..end_date
  end
end

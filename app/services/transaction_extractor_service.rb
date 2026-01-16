class TransactionExtractorService
  class Error < StandardError; end
  class ExtractionError < Error; end

  attr_reader :chunks, :account, :on_progress

  # Initialize with text chunks and account
  # @param chunks [Array<String>, String] Text chunks to process (or single string for backward compatibility)
  # @param account [Account] The account for transactions
  # @param on_progress [Proc, nil] Optional callback called with (current_chunk, total_chunks)
  def initialize(chunks, account, on_progress: nil)
    @chunks = chunks.is_a?(Array) ? chunks : [ chunks ]
    @account = account
    @on_progress = on_progress
  end

  # For backward compatibility - returns first chunk's text
  def text
    @chunks.first
  end

  # Extract transactions from all chunks using Ollama
  # @return [Array<Hash>] Array of transaction hashes
  def extract
    unless OllamaService.available?
      raise ExtractionError, "Ollama is not available. Please ensure it is running."
    end

    all_transactions = []
    total = @chunks.size

    @chunks.each_with_index do |chunk, index|
      current = index + 1
      Rails.logger.info "Processing chunk #{current}/#{total}"
      @on_progress&.call(current, total)

      prompt = build_prompt(chunk)
      response = OllamaService.generate_json(prompt)

      transactions = parse_response(response)
      normalized = validate_and_normalize(transactions)
      all_transactions.concat(normalized)
    end

    all_transactions
  rescue OllamaService::Error => e
    raise ExtractionError, "Failed to extract transactions: #{e.message}"
  end

  private

  def build_prompt(chunk_text)
    expense_categories = Category.expense.pluck(:name).join(", ")
    income_categories = Category.income.pluck(:name).join(", ")
    current_year = Date.today.year

    <<~PROMPT
      You are a financial transaction parser. Extract all transactions from the following bank statement or financial document.

      ACCOUNT CURRENCY: #{account.currency}
      CURRENT YEAR: #{current_year}

      IMPORTANT RULES:
      1. Extract EVERY transaction you can find
      2. Dates should be in YYYY-MM-DD format
      3. Amounts should be positive numbers with exactly two decimal places (e.g., 123.45, 10.00), no currency symbols
      4. For type: use "expense" for money going out (purchases, payments, withdrawals) and "income" for money coming in (deposits, transfers in, refunds)
      5. Match each transaction to the most appropriate category from the lists below
      6. If no category fits well, use "Other" as the category
      7. When a transaction shows both a foreign currency amount AND an amount in #{account.currency}, always use the #{account.currency} amount
      8. IGNORE summary lines like "Total", "Subtotal", "Balance", "Zwischensumme", "Saldo", or any aggregated amounts - only extract individual transactions
      9. If a transaction has multiple dates, use the "Date" or "Datum" field, NOT "Valuta", "Value Date", or "Buchungsdatum"

      DATE PARSING RULES (CRITICAL - PAY CLOSE ATTENTION):
      - This is a EUROPEAN document. Dates are ALWAYS in format DD.MM.YY or DD.MM.YYYY
      - The FIRST number is the DAY (1-31), the SECOND number is the MONTH (1-12)
      - Example: "07.11.25" → Day=07, Month=11 (November) → output "2025-11-07"
      - Example: "23.01.25" → Day=23, Month=01 (January) → output "2025-01-23"
      - Example: "15.03.2025" → Day=15, Month=03 (March) → output "2025-03-15"
      - NEVER interpret the first number as month - that would be American format which is NOT used here
      - Two-digit years (e.g., "25") mean 20XX (2025, not 1925)
      - Bank statements typically cover 1-2 consecutive months, so all dates should be within a reasonable range
      - If only day and month are shown, assume the year is #{current_year} or #{current_year - 1} based on context

      AVAILABLE EXPENSE CATEGORIES: #{expense_categories.presence || "Other"}
      AVAILABLE INCOME CATEGORIES: #{income_categories.presence || "Other"}

      OUTPUT FORMAT (JSON only, no other text):
      {
        "transactions": [
          {
            "date": "YYYY-MM-DD",
            "description": "merchant or description",
            "amount": 123.45,
            "type": "expense",
            "category": "category name"
          }
        ]
      }

      If you cannot find any transactions, return: {"transactions": []}

      BANK STATEMENT TEXT:
      ---
      #{chunk_text.truncate(8000)}
      ---
    PROMPT
  end

  def parse_response(response)
    # Handle various response formats from the LLM
    transactions = case response
    when Array
      # LLM returned array directly
      response
    when Hash
      # Try common wrapper keys
      response["transactions"] || response["data"] || response["results"] || []
    else
      raise ExtractionError, "Invalid response format: expected Hash or Array, got #{response.class}"
    end

    unless transactions.is_a?(Array)
      raise ExtractionError, "Invalid response format: expected 'transactions' array, got #{transactions.class}"
    end

    transactions
  end

  def validate_and_normalize(transactions)
    transactions.filter_map do |txn|
      # Normalize field names first
      txn = normalize_field_names(txn)

      # Skip transactions missing required data (instead of failing entirely)
      unless valid_transaction?(txn)
        Rails.logger.warn "Skipping invalid transaction: #{txn.inspect}"
        next
      end

      normalize_transaction(txn)
    end
  end

  def normalize_field_names(txn)
    # Handle various field name formats the LLM might use
    {
      "date" => txn["date"] || txn["transaction_date"] || txn["Date"],
      "description" => txn["description"] || txn["name"] || txn["merchant"] || txn["Description"] || txn["memo"],
      "amount" => txn["amount"] || txn["value"] || txn["Amount"],
      "type" => txn["type"] || txn["transaction_type"] || txn["Type"] || infer_type(txn),
      "category" => txn["category"] || txn["Category"]
    }
  end

  def infer_type(txn)
    # Try to infer type from other fields if not explicitly provided
    if txn["credit"].present? || txn["deposit"].present?
      "income"
    elsif txn["debit"].present? || txn["withdrawal"].present?
      "expense"
    end
  end

  def valid_transaction?(txn)
    txn["date"].present? &&
      txn["description"].present? &&
      txn["amount"].present?
  end

  def normalize_transaction(txn)
    date = parse_date(txn["date"])
    type = txn["type"].to_s.downcase == "income" ? "income" : "expense"
    category = find_category(txn["category"], type)

    {
      date: date,
      description: txn["description"].to_s.strip,
      amount: txn["amount"].to_f.abs.round(2),
      transaction_type: type,
      category_id: category&.id,
      category_name: category&.name || txn["category"],
      account_id: account.id
    }
  end

  def parse_date(date_str)
    Date.parse(date_str.to_s)
  rescue ArgumentError
    # Try to be flexible with date parsing
    Date.today
  end

  def find_category(name, type)
    return nil if name.blank?

    # Try exact match first
    category = Category.find_by(name: name, category_type: type)
    return category if category

    # Try case-insensitive match
    category = Category.where(category_type: type)
                       .where("LOWER(name) = ?", name.downcase.strip)
                       .first
    return category if category

    # Try partial match
    Category.where(category_type: type)
            .where("LOWER(name) LIKE ?", "%#{name.downcase.strip}%")
            .first
  end
end

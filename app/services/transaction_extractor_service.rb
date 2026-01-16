class TransactionExtractorService
  class Error < StandardError; end
  class ExtractionError < Error; end

  CATEGORY_BATCH_SIZE = 10

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

    # Step 1: Extract transactions from PDF chunks
    all_transactions = extract_from_chunks

    # Step 2: Assign categories in batches
    categorize_transactions(all_transactions)

    all_transactions
  rescue OllamaService::Error => e
    raise ExtractionError, "Failed to extract transactions: #{e.message}"
  end

  private

  # Step 1: Extract raw transactions from document chunks
  def extract_from_chunks
    all_transactions = []
    total_steps = @chunks.size + 1 # +1 for categorization step

    @chunks.each_with_index do |chunk, index|
      current = index + 1
      Rails.logger.info "Extracting from chunk #{current}/#{@chunks.size}"
      @on_progress&.call(current, total_steps)

      prompt = build_extraction_prompt(chunk)
      response = OllamaService.generate_json(prompt)

      transactions = parse_response(response)
      normalized = validate_and_normalize(transactions)
      all_transactions.concat(normalized)
    end

    all_transactions
  end

  # Step 2: Assign categories in batches
  def categorize_transactions(transactions)
    return if transactions.empty?

    total_steps = @chunks.size + 1
    @on_progress&.call(total_steps, total_steps)
    Rails.logger.info "Categorizing #{transactions.size} transactions"

    expense_categories = Category.expense.pluck(:name)
    income_categories = Category.income.pluck(:name)

    transactions.each_slice(CATEGORY_BATCH_SIZE) do |batch|
      categorize_batch(batch, expense_categories, income_categories)
    end
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
    # Leave transactions without categories rather than failing
  end

  def build_extraction_prompt(chunk_text)
    <<~PROMPT
      You are a financial transaction parser. Extract all transactions from the following financial statement.

      ACCOUNT CURRENCY: #{account.currency}

      RULES:
      1. Extract EVERY transaction you can find
      2. Dates must be in YYYY-MM-DD format
      3. Amounts must be positive numbers with two decimal places (e.g., 123.45), no currency symbols
      4. Type: "expense" for money out, "income" for money in
      5. When both foreign currency and #{account.currency} amounts shown, use the #{account.currency} amount
      6. IGNORE summary lines (Total, Subtotal, Balance, Zwischensumme, Saldo)
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

    <<~PROMPT
      Categorize these financial transactions. Pick the single best category for each.

      EXPENSE CATEGORIES: #{expense_categories.join(", ")}
      INCOME CATEGORIES: #{income_categories.join(", ")}

      TRANSACTIONS:
      #{txn_list}

      OUTPUT FORMAT (JSON array of category names, same order as input):
      ["category1", "category2", ...]

      Use "Other" if no category fits well.
    PROMPT
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
      response["categories"] || response.values.first || []
    else
      []
    end

    # Ensure all categories are strings
    categories.map { |c| c.to_s.presence }
  end

  def validate_and_normalize(transactions)
    transactions.filter_map do |txn|
      txn = normalize_field_names(txn)

      unless valid_transaction?(txn)
        Rails.logger.warn "Skipping invalid transaction: #{txn.inspect}"
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
      "type" => txn["type"] || txn["transaction_type"] || txn["Type"] || infer_type(txn)
    }
  end

  def infer_type(txn)
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
    Date.parse(date_str.to_s)
  rescue ArgumentError
    Date.today
  end

  def find_category(name, type)
    return nil if name.blank?

    name_str = name.to_s.strip
    return nil if name_str.empty?

    # Try exact match first
    category = Category.find_by(name: name_str, category_type: type)
    return category if category

    # Try case-insensitive match
    category = Category.where(category_type: type)
                       .where("LOWER(name) = ?", name_str.downcase)
                       .first
    return category if category

    # Try partial match
    Category.where(category_type: type)
            .where("LOWER(name) LIKE ?", "%#{name_str.downcase}%")
            .first
  end
end

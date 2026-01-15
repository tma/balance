class TransactionExtractorService
  class Error < StandardError; end
  class ExtractionError < Error; end

  attr_reader :text, :account

  def initialize(text, account)
    @text = text
    @account = account
  end

  # Extract transactions from the text using Ollama
  # @return [Array<Hash>] Array of transaction hashes
  def extract
    unless OllamaService.available?
      raise ExtractionError, "Ollama is not available. Please ensure it is running."
    end

    prompt = build_prompt
    response = OllamaService.generate_json(prompt)

    transactions = parse_response(response)
    validate_and_normalize(transactions)
  rescue OllamaService::Error => e
    raise ExtractionError, "Failed to extract transactions: #{e.message}"
  end

  private

  def build_prompt
    expense_categories = Category.expense.pluck(:name).join(", ")
    income_categories = Category.income.pluck(:name).join(", ")

    <<~PROMPT
      You are a financial transaction parser. Extract all transactions from the following bank statement or financial document.

      IMPORTANT RULES:
      1. Extract EVERY transaction you can find
      2. Dates should be in YYYY-MM-DD format
      3. Amounts should be positive numbers (no currency symbols)
      4. For type: use "expense" for money going out (purchases, payments, withdrawals) and "income" for money coming in (deposits, transfers in, refunds)
      5. Match each transaction to the most appropriate category from the lists below
      6. If no category fits well, use "Other" as the category

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
      #{text.truncate(8000)}
      ---
    PROMPT
  end

  def parse_response(response)
    transactions = response["transactions"]

    unless transactions.is_a?(Array)
      raise ExtractionError, "Invalid response format: expected 'transactions' array"
    end

    transactions
  end

  def validate_and_normalize(transactions)
    transactions.map do |txn|
      validate_transaction!(txn)
      normalize_transaction(txn)
    end
  end

  def validate_transaction!(txn)
    required_fields = %w[date description amount type]
    missing = required_fields.reject { |f| txn[f].present? }

    if missing.any?
      raise ExtractionError, "Transaction missing required fields: #{missing.join(', ')}"
    end
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

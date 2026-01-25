require "csv"

# Parses CSV transactions using a pre-determined column mapping
# No LLM involved - pure deterministic Ruby parsing
class DeterministicCsvParserService
  class Error < StandardError; end
  class ParseError < Error; end

  attr_reader :content, :mapping, :account

  # @param content [String] Full CSV content
  # @param mapping [Hash] Column mapping from CsvMappingAnalyzerService
  # @param account [Account] The account for transactions
  def initialize(content, mapping, account)
    @content = content
    @mapping = mapping
    @account = account
  end

  # Parse all transactions from CSV
  # @return [Array<Hash>] Array of transaction hashes
  def parse
    delimiter = detect_delimiter(content.lines.first || "")
    rows = CSV.parse(content, headers: true, liberal_parsing: true, col_sep: delimiter)
    transactions = []
    errors = []

    rows.each_with_index do |row, index|
      begin
        txn = parse_row(row)
        transactions << txn if txn
      rescue => e
        errors << "Row #{index + 2}: #{e.message}"
        Rails.logger.warn "CSV parse error at row #{index + 2}: #{e.message}"
      end
    end

    if transactions.empty? && errors.any?
      raise ParseError, "Failed to parse any transactions. First error: #{errors.first}"
    end

    transactions
  rescue CSV::MalformedCSVError => e
    raise ParseError, "Invalid CSV format: #{e.message}"
  end

  private

  def detect_delimiter(line)
    # Count occurrences of common delimiters
    semicolons = line.count(";")
    commas = line.count(",")
    tabs = line.count("\t")

    # Return the most frequent delimiter (semicolon preferred over comma if equal)
    if semicolons >= commas && semicolons >= tabs
      ";"
    elsif tabs > commas
      "\t"
    else
      ","
    end
  end

  def parse_row(row)
    date = parse_date(row[mapping[:date_column]])
    return nil unless date

    description = build_description(row)
    return nil if description.blank?
    return nil if account.should_ignore_for_import?(description)

    amount, transaction_type = parse_amount_and_type(row)
    return nil unless amount && amount > 0

    {
      date: date,
      description: description,
      amount: amount.round(2),
      transaction_type: transaction_type,
      category_id: nil,
      category_name: nil,
      account_id: account.id
    }
  end

  def build_description(row)
    primary = row[mapping[:description_column]].to_s.strip
    secondary_column = mapping[:description_secondary_column]

    if secondary_column.present?
      secondary = row[secondary_column].to_s.strip
      if primary.present? && secondary.present? && secondary != primary
        return "#{primary} - #{secondary}"
      elsif secondary.present? && primary.blank?
        return secondary
      end
    end

    primary
  end

  def parse_date(value)
    return nil if value.blank?

    date_str = value.to_s.strip
    format = mapping[:date_format]

    begin
      Date.strptime(date_str, format)
    rescue ArgumentError
      # Try common fallback formats
      try_fallback_date_formats(date_str)
    end
  end

  def try_fallback_date_formats(date_str)
    fallback_formats = [
      "%Y-%m-%d",   # 2024-01-15
      "%d.%m.%Y",   # 15.01.2024
      "%d.%m.%y",   # 15.01.24
      "%m/%d/%Y",   # 01/15/2024
      "%d/%m/%Y",   # 15/01/2024
      "%Y/%m/%d"    # 2024/01/15
    ]

    fallback_formats.each do |fmt|
      begin
        return Date.strptime(date_str, fmt)
      rescue ArgumentError
        next
      end
    end

    # Last resort: let Ruby try to parse it
    Date.parse(date_str)
  rescue ArgumentError
    nil
  end

  def parse_amount_and_type(row)
    if mapping[:amount_type] == "split"
      parse_split_amount(row)
    else
      parse_single_amount(row)
    end
  end

  def parse_single_amount(row)
    raw_value = row[mapping[:amount_column]].to_s.strip
    return [ nil, nil ] if raw_value.blank?

    amount = parse_amount_value(raw_value)
    return [ nil, nil ] if amount.nil?

    if amount < 0
      [ amount.abs, invert_type("expense") ]
    else
      [ amount, invert_type("income") ]
    end
  end

  def parse_split_amount(row)
    debit_raw = row[mapping[:debit_column]].to_s.strip
    credit_raw = row[mapping[:credit_column]].to_s.strip

    debit = parse_amount_value(debit_raw) if debit_raw.present?
    credit = parse_amount_value(credit_raw) if credit_raw.present?

    if debit && debit != 0
      [ debit.abs, invert_type("expense") ]
    elsif credit && credit != 0
      [ credit.abs, invert_type("income") ]
    else
      [ nil, nil ]
    end
  end

  # Inverts the transaction type if the account type requires it (e.g., credit cards).
  # For credit cards, positive amounts in CSV are purchases (expenses) and
  # negative amounts are payments/refunds (income), which is opposite of normal accounts.
  def invert_type(type)
    return type unless account.account_type&.invert_amounts_on_import

    type == "income" ? "expense" : "income"
  end

  def parse_amount_value(raw_value)
    return nil if raw_value.blank?

    # Remove currency symbols and whitespace
    cleaned = raw_value.gsub(/[^\d.,\-+]/, "").strip
    return nil if cleaned.blank?

    case mapping[:amount_format]
    when "eu"
      # European: 1.234,56 -> 1234.56 OR 45,80 -> 45.80
      if cleaned.include?(",")
        # Has comma - comma is decimal separator
        # Remove dots (thousands) and replace comma with dot
        cleaned = cleaned.gsub(".", "").gsub(",", ".")
      else
        # No comma - the dot (if any) is the decimal separator
        # Leave as-is, it's already in a parseable format
      end
    when "us"
      # US: 1,234.56 -> 1234.56
      cleaned = cleaned.gsub(",", "")
    else
      # Plain or unknown: try to detect
      cleaned = auto_detect_and_normalize(cleaned)
    end

    Float(cleaned)
  rescue ArgumentError, TypeError
    nil
  end

  def auto_detect_and_normalize(value)
    # If has both . and , figure out which is decimal separator
    if value.include?(".") && value.include?(",")
      # Last separator is likely the decimal
      if value.rindex(",") > value.rindex(".")
        # EU format: 1.234,56
        value.gsub(".", "").gsub(",", ".")
      else
        # US format: 1,234.56
        value.gsub(",", "")
      end
    elsif value.include?(",")
      # Could be EU decimal or US thousands
      # If comma is followed by exactly 2 digits at end, treat as decimal
      if value.match?(/,\d{2}$/)
        value.gsub(",", ".")
      else
        value.gsub(",", "")
      end
    else
      value
    end
  end
end

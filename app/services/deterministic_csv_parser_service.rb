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
    @detail_columns = nil
  end

  # Parse all transactions from CSV
  # @return [Array<Hash>] Array of transaction hashes
  def parse
    delimiter = detect_delimiter(content.lines.first || "")
    rows = CSV.parse(content, headers: true, liberal_parsing: true, col_sep: delimiter)

    # Auto-detect columns if not explicitly provided
    detect_secondary_description_column(rows.headers)
    detect_detail_columns(rows) if should_detect_detail_columns?

    transactions = []
    errors = []
    current_group = nil

    rows.each_with_index do |row, index|
      begin
        # Check if this is a header row (has a date) or detail row (no date)
        row_date = parse_date(row[mapping[:date_column]])

        if row_date
          # Flush previous group before starting new one
          flush_group(current_group, transactions) if current_group
          current_group = nil

          # Header row - parse it
          txn = parse_row(row, row_date)
          if txn && has_detail_columns?
            # Start a new group - we'll decide later if this is a summary row
            current_group = { header: txn, details: [], header_date: row_date }
          elsif txn
            # No detail columns expected, just add the transaction
            transactions << txn
          end
        elsif has_detail_columns? && current_group
          # Detail row in grouped format - use header's date
          txn = parse_detail_row(row, current_group[:header_date])
          current_group[:details] << txn if txn
        end
      rescue => e
        errors << "Row #{index + 2}: #{e.message}"
        Rails.logger.warn "CSV parse error at row #{index + 2}: #{e.message}"
      end
    end

    # Flush final group
    flush_group(current_group, transactions) if current_group

    if transactions.empty? && errors.any?
      raise ParseError, "Failed to parse any transactions. First error: #{errors.first}"
    end

    transactions
  rescue CSV::MalformedCSVError => e
    raise ParseError, "Invalid CSV format: #{e.message}"
  end

  private

  # Flush a transaction group, deciding whether to include the header row
  # If detail rows sum to header amount (within tolerance), skip the header (it's a summary)
  def flush_group(group, transactions)
    return unless group

    header = group[:header]
    details = group[:details]

    if details.any?
      # Check if details sum to header amount (summary row detection)
      details_sum = details.sum { |d| d[:amount] }
      header_amount = header[:amount]

      # Allow 1% tolerance for rounding differences
      is_summary = (details_sum - header_amount).abs < (header_amount * 0.01 + 0.01)

      if is_summary
        # Skip header row - it's just a summary of the details
        Rails.logger.debug "Skipping summary row '#{header[:description]}' (#{header_amount}) - details sum to #{details_sum}"
      else
        # Include header row - it's a separate transaction
        transactions << header
      end

      # Always include detail rows
      transactions.concat(details)
    else
      # No details - just include the header as a regular transaction
      transactions << header
    end
  end

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

  # Check if we should try to auto-detect detail columns
  def should_detect_detail_columns?
    !mapping[:detail_amount_column].present? || !mapping[:detail_description_column].present?
  end

  # Check if detail columns are available (either from mapping or auto-detected)
  def has_detail_columns?
    detail_amount_column.present? && detail_description_column.present?
  end

  def detail_amount_column
    mapping[:detail_amount_column] || @detail_columns&.dig(:amount)
  end

  def detail_description_column
    mapping[:detail_description_column] || @detail_columns&.dig(:description)
  end

  # Auto-detect columns that contain data only on rows without dates
  # These are likely detail row columns for grouped transactions
  def detect_detail_columns(rows)
    date_col = mapping[:date_column]
    main_desc_col = mapping[:description_column]
    main_amount_cols = [ mapping[:amount_column], mapping[:debit_column], mapping[:credit_column] ].compact

    # Track which columns have data on date vs no-date rows
    date_row_columns = Set.new
    no_date_row_columns = {}

    rows.each do |row|
      has_date = row[date_col].to_s.strip.present?

      row.headers.each do |col|
        next if col.nil?
        value = row[col].to_s.strip
        next if value.blank?

        if has_date
          date_row_columns << col
        else
          no_date_row_columns[col] ||= []
          no_date_row_columns[col] << value
        end
      end
    end

    # Find columns that appear primarily on no-date rows and not on date rows
    # Exclude main mapping columns
    excluded = [ date_col, main_desc_col, mapping[:description_secondary_column] ] + main_amount_cols
    candidate_columns = no_date_row_columns.keys - date_row_columns.to_a - excluded.compact

    return if candidate_columns.empty?

    # Find a description column (text values) and amount column (numeric values)
    amount_col = nil
    desc_col = nil

    candidate_columns.each do |col|
      values = no_date_row_columns[col]
      next if values.empty?

      # Check if values look like amounts (mostly numeric)
      numeric_count = values.count { |v| v.gsub(/[^\d.,\-+]/, "").match?(/\d/) }

      if numeric_count > values.size / 2
        amount_col ||= col
      else
        desc_col ||= col
      end
    end

    if amount_col && desc_col
      @detail_columns = { amount: amount_col, description: desc_col }
      Rails.logger.info "Auto-detected detail columns: amount=#{amount_col}, description=#{desc_col}"
    end
  end

  # Known patterns for secondary description columns (case-insensitive)
  SECONDARY_DESCRIPTION_PATTERNS = [
    # German
    /zahlungszweck/i, /verwendungszweck/i, /mitteilung/i, /bemerkung/i,
    /buchungstext/i, /beschreibung/i,
    # English
    /\bmemo\b/i, /\bdetails?\b/i, /\bnotes?\b/i, /\bnarrative\b/i,
    /\bpurpose\b/i, /\bremarks?\b/i, /\bdescription\b/i,
    # French
    /\blibelle\b/i, /\bmotif\b/i,
    # Generic
    /\btext\b/i, /\binfo\b/i
  ].freeze

  # Columns to ignore as descriptions (case-insensitive)
  IGNORE_DESCRIPTION_PATTERNS = [
    /\bwhg\b/i, /\bcurrency\b/i, /währung/i, /\bdevise\b/i,
    /\bref(erenz|erence)?\b/i, /\bid\b/i, /\bnumber\b/i, /\bnummer\b/i,
    /\bvaluta\b/i, /\bsaldo\b/i, /\bbalance\b/i,
    /\bdate\b/i, /\bdatum\b/i
  ].freeze

  # Auto-detect secondary description column if not provided by LLM
  def detect_secondary_description_column(headers)
    return if mapping[:description_secondary_column].present?

    primary = mapping[:description_column]
    excluded = [ primary, mapping[:date_column], mapping[:amount_column],
                 mapping[:debit_column], mapping[:credit_column] ].compact

    candidates = headers - excluded

    # First pass: look for known secondary description patterns
    SECONDARY_DESCRIPTION_PATTERNS.each do |pattern|
      match = candidates.find { |col| col.match?(pattern) && col != primary }
      if match && !IGNORE_DESCRIPTION_PATTERNS.any? { |p| match.match?(p) }
        @detected_secondary_description = match
        Rails.logger.info "Auto-detected secondary description column: #{match}"
        return
      end
    end
  end

  def secondary_description_column
    mapping[:description_secondary_column] || @detected_secondary_description
  end

  def parse_row(row, date)
    description = build_description(row)
    return nil if description.blank?

    amount, transaction_type = parse_amount_and_type(row)
    return nil unless amount && amount > 0

    {
      date: date,
      description: description,
      amount: amount.round(2),
      transaction_type: transaction_type,
      category_id: nil,
      category_name: nil,
      account_id: account.id,
      is_ignored: account.should_ignore_for_import?(description)
    }
  end

  # Parse a detail row (no date, inherits from header row)
  def parse_detail_row(row, date)
    description = build_description(row)
    return nil if description.blank?

    raw_amount = row[detail_amount_column].to_s.strip
    return nil if raw_amount.blank?

    amount = parse_amount_value(raw_amount)
    return nil unless amount && amount > 0

    # Detail rows are typically expenses (sub-items of a grouped payment)
    transaction_type = invert_type("expense")

    {
      date: date,
      description: description,
      amount: amount.abs.round(2),
      transaction_type: transaction_type,
      category_id: nil,
      category_name: nil,
      account_id: account.id,
      is_ignored: account.should_ignore_for_import?(description)
    }
  end

  def build_description(row)
    # Collect all non-empty description values from configured columns
    parts = []

    # Primary description column
    primary = row[mapping[:description_column]].to_s.strip
    parts << primary if primary.present?

    # Secondary description column (from LLM or auto-detected)
    sec_col = secondary_description_column
    if sec_col.present?
      secondary = row[sec_col].to_s.strip
      parts << secondary if secondary.present? && secondary != primary
    end

    # Detail description column (for detail rows, but also check on all rows)
    if detail_description_column.present?
      detail = row[detail_description_column].to_s.strip
      parts << detail if detail.present? && !parts.include?(detail)
    end

    parts.uniq.join(" - ")
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

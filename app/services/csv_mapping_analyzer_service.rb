# Analyzes CSV structure using LLM to determine column mappings
# Returns a mapping that can be used by DeterministicCsvParserService
class CsvMappingAnalyzerService
  class Error < StandardError; end
  class AnalysisError < Error; end

  SAMPLE_ROWS = 5

  class << self
    # Analyze CSV structure and return column mapping
    # @param content [String] Full CSV content
    # @return [Hash] Mapping configuration
    def analyze(content)
      lines = content.lines
      raise AnalysisError, "CSV file is empty" if lines.empty?

      header = lines.first.strip
      sample_rows = lines.drop(1).reject { |l| l.strip.empty? }.first(SAMPLE_ROWS)

      raise AnalysisError, "CSV has no data rows" if sample_rows.empty?

      sample_csv = ([ header ] + sample_rows).join("\n")

      prompt = build_prompt(sample_csv)
      response = OllamaService.generate_json(prompt)

      mapping = parse_response(response)
      validate_mapping!(mapping, header)

      mapping
    rescue OllamaService::Error => e
      raise AnalysisError, "LLM analysis failed: #{e.message}"
    end

    private

    def build_prompt(sample_csv)
      <<~PROMPT
        Analyze this CSV and identify the column mappings for a financial transaction import.

        CSV SAMPLE (header + first rows):
        ```
        #{sample_csv}
        ```

        TASK: Identify the columns and formats by examining BOTH headers AND data values.

        1. DATE COLUMN (IMPORTANT):#{' '}
           - Choose the date when the transaction ACTUALLY HAPPENED
           - Prefer columns named: "Date", "Transaction Date", "Datum", "Buchungsdatum", "Trans Date"
           - AVOID accounting/settlement dates: "ValutaDate", "Valuta", "Value Date", "Posting Date", "Settlement Date", "Effective Date"
           - These valuta/settlement dates are when money moves between banks, NOT when you made the purchase
           - If you see both "Date" and "ValutaDate", always choose "Date"

        2. DESCRIPTION COLUMNS:#{' '}
           - Primary: merchant name or main description
           - Secondary (optional): additional details, memo, or notes to append
           - If there are two useful text columns (e.g., "MerchantName" + "Details"), include both

        3. AMOUNT COLUMNS - Look at the data carefully:
           - If ONE column has both positive and negative numbers → "single" (amount_column)
           - If TWO separate columns for money out/in (one often empty per row) → "split" (debit_column + credit_column)
           - German: "Soll" = debit (expense), "Haben" = credit (income)
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

    def parse_response(response)
      mapping = case response
      when Hash
        response.transform_keys(&:to_s)
      else
        raise AnalysisError, "Invalid response format: expected Hash, got #{response.class}"
      end

      # Normalize keys to symbols
      {
        date_column: mapping["date_column"],
        description_column: mapping["description_column"],
        description_secondary_column: mapping["description_secondary_column"],
        amount_type: mapping["amount_type"] || "single",
        amount_column: mapping["amount_column"],
        debit_column: mapping["debit_column"],
        credit_column: mapping["credit_column"],
        date_format: normalize_date_format(mapping["date_format"]),
        amount_format: mapping["amount_format"] || "plain"
      }
    end

    def normalize_date_format(format_str)
      return "%Y-%m-%d" if format_str.blank?

      # Convert human-readable formats to strptime format
      format_str
        .gsub(/YYYY/, "%Y")
        .gsub(/YY/, "%y")
        .gsub(/MM/, "%m")
        .gsub(/DD/, "%d")
        .gsub(/\bM\b/, "%-m")
        .gsub(/\bD\b/, "%-d")
    end

    def validate_mapping!(mapping, header)
      columns = parse_header_columns(header)

      # Check required columns exist (case-insensitive matching with correction)
      mapping[:date_column] = find_column(columns, mapping[:date_column], "Date")
      mapping[:description_column] = find_column(columns, mapping[:description_column], "Description")

      if mapping[:amount_type] == "single"
        mapping[:amount_column] = find_column(columns, mapping[:amount_column], "Amount")
      else
        mapping[:debit_column] = find_column(columns, mapping[:debit_column], "Debit")
        mapping[:credit_column] = find_column(columns, mapping[:credit_column], "Credit")
      end

      # Also fix secondary description column if present
      if mapping[:description_secondary_column].present?
        actual = columns.find { |c| c.downcase == mapping[:description_secondary_column].downcase }
        mapping[:description_secondary_column] = actual # nil if not found, which is fine
      end
    end

    # Find column with case-insensitive matching, returning the actual column name
    def find_column(columns, expected, column_type)
      return expected if columns.include?(expected)

      # Try case-insensitive match
      actual = columns.find { |c| c.downcase == expected.to_s.downcase }
      return actual if actual

      # No match found
      raise AnalysisError, "#{column_type} column '#{expected}' not found in CSV headers. Available: #{columns.join(', ')}"
    end

    def parse_header_columns(header)
      require "csv"
      # Detect delimiter: semicolon-delimited CSVs are common in European exports
      delimiter = detect_delimiter(header)
      CSV.parse_line(header, col_sep: delimiter).map(&:to_s).map(&:strip)
    rescue CSV::MalformedCSVError
      # Fallback to simple split using detected delimiter
      delimiter = detect_delimiter(header)
      header.split(delimiter).map(&:strip).map { |c| c.gsub(/^"|"$/, "") }
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
  end
end

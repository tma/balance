require "open3"

# Extracts transaction data from PDF bank statements using pdftotext + LLM
# Returns CSV string that can be processed by the existing CSV pipeline
class PdfTextExtractorService
  class Error < StandardError; end

  MAX_FILE_SIZE = 5.megabytes
  MAX_TEXT_LENGTH = 50_000 # Limit text sent to LLM

  class << self
    # Extract transactions from PDF and return as CSV string
    # @param file [ActionDispatch::Http::UploadedFile, File, IO, String] The PDF file or path
    # @return [String] CSV content from extracted transactions
    def extract_csv(file)
      validate_file_size!(file)

      pdf_path = file_to_path(file)
      raw_text = extract_text(pdf_path)

      if raw_text.blank?
        raise Error, "Could not extract text from PDF. The file may be empty or image-based."
      end

      convert_to_csv(raw_text)
    end

    private

    def validate_file_size!(file)
      size = if file.respond_to?(:size)
        file.size
      elsif file.respond_to?(:tempfile)
        file.tempfile.size
      elsif file.is_a?(String) && File.exist?(file)
        File.size(file)
      else
        0
      end

      if size > MAX_FILE_SIZE
        raise Error, "File too large. Maximum size is #{MAX_FILE_SIZE / 1.megabyte}MB"
      end
    end

    def file_to_path(file)
      if file.is_a?(String) && File.exist?(file)
        file
      elsif file.respond_to?(:tempfile)
        file.tempfile.path
      elsif file.respond_to?(:path)
        file.path
      elsif file.respond_to?(:read)
        # Create a temp file for IO objects
        temp = Tempfile.new([ "pdf_extract", ".pdf" ])
        temp.binmode
        file.rewind if file.respond_to?(:rewind)
        temp.write(file.read)
        temp.close
        temp.path
      else
        raise Error, "Unable to process file: #{file.class}"
      end
    end

    # Extract text from PDF using pdftotext with layout preservation
    # The -layout flag maintains column alignment via spacing
    def extract_text(pdf_path)
      stdout, stderr, status = Open3.capture3("pdftotext", "-layout", pdf_path, "-")

      unless status.success?
        Rails.logger.error "pdftotext failed: #{stderr}"
        raise Error, "Failed to extract text from PDF"
      end

      stdout
    end

    # Use LLM to convert extracted text to CSV format
    def convert_to_csv(text)
      # Truncate very long documents to avoid LLM context limits
      truncated_text = text.length > MAX_TEXT_LENGTH ? text[0, MAX_TEXT_LENGTH] : text

      prompt = build_prompt(truncated_text)
      response = OllamaService.generate(prompt)

      csv_content = extract_csv_from_response(response)

      if csv_content.blank?
        raise Error, "Could not extract transactions from PDF. Try uploading a CSV export instead."
      end

      csv_content
    rescue OllamaService::Error => e
      raise Error, "AI extraction failed: #{e.message}"
    end

    def build_prompt(text)
      <<~PROMPT
        You are a financial document parser. Extract the transaction table from this bank/credit card statement and output as CSV.

        DOCUMENT TEXT:
        ```
        #{text}
        ```

        INSTRUCTIONS:
        1. Find the transaction table in the document
        2. Output ONLY valid CSV data (no markdown, no explanations)
        3. Include a header row with the original column names from the document
        4. Include columns for: date, description/merchant, and amount (or separate debit/credit columns)
        5. Keep amounts in their original format (with currency symbols, negative signs, European format, etc.)
        6. Keep dates in their original format
        7. Skip summary rows, totals, and non-transaction lines
        8. If there are multiple transaction tables, combine them into one CSV

        Output the CSV now:
      PROMPT
    end

    # Extract CSV content from LLM response, handling markdown code blocks
    def extract_csv_from_response(response)
      return "" if response.blank?

      content = response.strip

      # Remove markdown code block if present
      if content.start_with?("```")
        # Remove opening ``` and optional language hint
        content = content.sub(/\A```(?:csv)?\s*\n?/, "")
        # Remove closing ```
        content = content.sub(/\n?```\s*\z/, "")
      end

      # Validate it looks like CSV (has commas or tabs, multiple lines)
      lines = content.lines.reject { |l| l.strip.empty? }
      if lines.size < 2
        Rails.logger.warn "LLM response doesn't look like valid CSV: #{content.truncate(200)}"
        return ""
      end

      content.strip
    end
  end
end

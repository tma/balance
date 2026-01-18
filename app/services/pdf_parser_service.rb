require "set"

class PdfParserService
  class Error < StandardError; end

  MAX_FILE_SIZE = 5.megabytes

  class << self
    # Extract text from a PDF file using OCR, returning an array of pages
    # @param file [ActionDispatch::Http::UploadedFile, File, IO, String] The PDF file or path
    # @return [Array<String>] Array of text content per page
    def extract_pages(file)
      validate_file_size!(file)

      unless OcrService.available?
        raise Error, "OCR is not available. Please ensure Tesseract and Poppler are installed."
      end

      io = normalize_io(file)
      pages = OcrService.extract_pages(io)

      if pages.empty?
        raise Error, "No text could be extracted from the PDF. It may be blank or corrupted."
      end

      cleanup_pages(pages)
    rescue OcrService::Error => e
      raise Error, "PDF extraction failed: #{e.message}"
    end

    # Extract all text as a single string (legacy method)
    # @param file [ActionDispatch::Http::UploadedFile, File, IO, String] The PDF file or path
    # @return [String] The extracted text
    def extract_text(file)
      extract_pages(file).join("\n\n")
    end

    # Alias for consistency (now that OCR is the only method)
    def extract_pages_with_ocr(file)
      extract_pages(file)
    end

    private

    def normalize_io(file)
      if file.respond_to?(:tempfile)
        file.tempfile.rewind
        file.tempfile
      elsif file.respond_to?(:read)
        file.rewind if file.respond_to?(:rewind)
        file
      else
        # Assume it's a file path
        file
      end
    end

    def validate_file_size!(file)
      size = if file.respond_to?(:size)
        file.size
      elsif file.respond_to?(:tempfile)
        file.tempfile.size
      else
        0
      end

      if size > MAX_FILE_SIZE
        raise Error, "File too large. Maximum size is #{MAX_FILE_SIZE / 1.megabyte}MB"
      end
    end

    def cleanup_pages(pages)
      normalized_pages = pages.map { |page| normalize_text(page) }
      repeated_lines = repeated_line_matches(normalized_pages)

      normalized_pages.map do |page|
        lines = page.lines.map(&:strip)
        cleaned_lines = lines.filter_map do |line|
          next if line.blank?
          next if repeated_lines.include?(line)
          next if drop_line?(line)
          line
        end

        merge_transaction_continuations(cleaned_lines)
      end
    end

    def normalize_text(text)
      text = text.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      text = text.tr("\u00A0", " ")
      text = text.gsub(/\r\n?/, "\n")

      text.lines.map do |line|
        line.gsub(/\t/, " ").gsub(/\s+/, " ").strip
      end.join("\n")
    end

    def repeated_line_matches(pages)
      line_counts = Hash.new(0)
      pages.each do |page|
        page.lines.map(&:strip).uniq.each do |line|
          line_counts[line] += 1
        end
      end

      line_counts.select { |line, count| count > 1 && line.length >= 8 }.keys.to_set
    end

    def drop_line?(line)
      return true if line.match?(/\ASeite\s*\d+\/\d+\z/i)
      return true if line.match?(/\A\d{1,2}\s*\/\s*\d{1,2}\z/)
      return true if line.match?(/\A\d+\z/)
      return true if line.match?(/\A[\p{P}\s]+\z/)

      lowered = line.downcase
      lowered.match?(TransactionExtractorService::NON_TRANSACTION_DESCRIPTION)
    end

    def merge_transaction_continuations(lines)
      merged = []
      lines.each do |line|
        if continuation_line?(line) && merged.any?
          merged[-1] = "#{merged[-1]} #{line}"
        else
          merged << line
        end
      end

      merged.join("\n")
    end

    def continuation_line?(line)
      return false if line.blank?
      return false if line.match?(/\A\d{1,2}\.\d{1,2}\.\d{2,4}\b/)

      !line.match?(/\b\d+[\.,']\d{2}\b/) && !line.match?(/\b\d{1,3}(?:[\.,']\d{3})+(?:[\.,]\d{2})\b/)
    end
  end
end

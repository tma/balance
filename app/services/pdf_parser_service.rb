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

      pages
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
  end
end

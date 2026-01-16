require "pdf-reader"

class PdfParserService
  class Error < StandardError; end

  MAX_FILE_SIZE = 5.megabytes

  class << self
    # Extract text from a PDF file
    # @param file [ActionDispatch::Http::UploadedFile, File, IO, String] The PDF file or path
    # @return [String] The extracted text
    def extract_text(file)
      validate_file_size!(file)

      # Handle ActionDispatch::Http::UploadedFile from form uploads
      io = if file.respond_to?(:tempfile)
        file.tempfile.rewind
        file.tempfile
      elsif file.respond_to?(:read)
        file.rewind if file.respond_to?(:rewind)
        file
      else
        # Assume it's a file path
        file
      end

      reader = PDF::Reader.new(io)
      text = reader.pages.map(&:text).join("\n\n")

      if text.strip.empty?
        raise Error, "No text could be extracted from the PDF. It may be image-based."
      end

      text
    rescue PDF::Reader::MalformedPDFError => e
      raise Error, "Invalid or corrupted PDF file: #{e.message}"
    rescue PDF::Reader::EncryptedPDFError
      raise Error, "Cannot read encrypted PDF files"
    end

    private

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

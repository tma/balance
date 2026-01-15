class CsvParserService
  class Error < StandardError; end

  MAX_FILE_SIZE = 5.megabytes
  MAX_LINES = 500 # Limit lines sent to LLM to avoid token limits

  class << self
    # Extract text from a CSV file
    # @param file [ActionDispatch::Http::UploadedFile, File, IO] The CSV file
    # @return [String] The CSV content as text
    def extract_text(file)
      validate_file_size!(file)

      content = read_file_content(file)

      if content.strip.empty?
        raise Error, "CSV file is empty"
      end

      # Limit to MAX_LINES to avoid overwhelming the LLM
      lines = content.lines
      if lines.size > MAX_LINES
        lines = lines.first(MAX_LINES)
        lines << "\n... (truncated, #{lines.size} of #{content.lines.size} lines shown)"
      end

      lines.join
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

    def read_file_content(file)
      if file.respond_to?(:read)
        content = file.read
        file.rewind if file.respond_to?(:rewind)
        content
      elsif file.respond_to?(:tempfile)
        File.read(file.tempfile.path)
      else
        File.read(file)
      end
    end
  end
end

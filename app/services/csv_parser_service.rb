class CsvParserService
  class Error < StandardError; end

  MAX_FILE_SIZE = 5.megabytes
  CHUNK_SIZE = 50 # Number of data rows per chunk (header included with each)

  class << self
    # Extract text from a CSV file, returning chunks of rows
    # @param file [ActionDispatch::Http::UploadedFile, File, IO] The CSV file
    # @return [Array<String>] Array of CSV chunks (header + rows)
    def extract_chunks(file)
      validate_file_size!(file)

      content = read_file_content(file)

      if content.strip.empty?
        raise Error, "CSV file is empty"
      end

      lines = content.lines
      return [ content ] if lines.size <= 1 # Just header or single line

      header = lines.first
      data_lines = lines.drop(1).reject { |line| line.strip.empty? }

      return [ content ] if data_lines.empty?

      # Split data lines into chunks, each with the header prepended
      data_lines.each_slice(CHUNK_SIZE).map do |chunk|
        header + chunk.join
      end
    end

    # Extract text as a single string (legacy method)
    # @param file [ActionDispatch::Http::UploadedFile, File, IO] The CSV file
    # @return [String] The CSV content as text
    def extract_text(file)
      validate_file_size!(file)

      content = read_file_content(file)

      if content.strip.empty?
        raise Error, "CSV file is empty"
      end

      # For legacy method, truncate if too long
      lines = content.lines
      if lines.size > CHUNK_SIZE * 10
        lines = lines.first(CHUNK_SIZE * 10)
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

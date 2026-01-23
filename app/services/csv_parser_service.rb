# Reads and normalizes CSV file content
# For actual parsing, use CsvMappingAnalyzerService + DeterministicCsvParserService
class CsvParserService
  class Error < StandardError; end

  MAX_FILE_SIZE = 5.megabytes

  class << self
    # Read CSV content from file
    # @param file [ActionDispatch::Http::UploadedFile, File, IO] The CSV file
    # @return [String] The normalized CSV content
    def read_content(file)
      validate_file_size!(file)

      content = read_file_content(file)

      if content.strip.empty?
        raise Error, "CSV file is empty"
      end

      content
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
      content = if file.respond_to?(:read)
        data = file.read
        file.rewind if file.respond_to?(:rewind)
        data
      elsif file.respond_to?(:tempfile)
        File.read(file.tempfile.path)
      else
        File.read(file)
      end

      normalize_encoding(content)
    end

    # Normalize content to valid UTF-8
    def normalize_encoding(content)
      content.force_encoding("UTF-8")
      return content if content.valid_encoding?

      %w[ISO-8859-1 Windows-1252 ASCII-8BIT].each do |encoding|
        begin
          converted = content.dup.force_encoding(encoding).encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
          return converted if converted.valid_encoding?
        rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
          next
        end
      end

      content.encode("UTF-8", "UTF-8", invalid: :replace, undef: :replace, replace: "")
    end
  end
end

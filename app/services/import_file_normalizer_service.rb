require "csv"
require "roo"

# Reads import files and normalizes content to CSV text for downstream parsing.
class ImportFileNormalizerService
  class Error < StandardError; end

  MAX_FILE_SIZE = 5.megabytes
  CSV_TYPES = [ "text/csv", "application/csv" ].freeze
  XLS_TYPE = "application/vnd.ms-excel".freeze
  XLSX_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze

  class << self
    # @param file [File, IO]
    # @param content_type [String]
    # @param filename [String]
    # @return [String] CSV text content
    def read_content(file, content_type:, filename:)
      validate_file_size!(file)

      format = detect_format(content_type, filename)

      case format
      when :csv
        CsvParserService.read_content(file)
      when :xlsx, :xls
        spreadsheet_to_csv(file, format)
      else
        raise Error, "Unsupported file type. Please upload CSV, XLS, or XLSX files."
      end
    end

    private

    def detect_format(content_type, filename)
      normalized_type = content_type.to_s.downcase
      extension = File.extname(filename.to_s.downcase)

      return :csv if CSV_TYPES.include?(normalized_type) || extension == ".csv"
      return :xlsx if normalized_type == XLSX_TYPE || extension == ".xlsx"
      return :xls if normalized_type == XLS_TYPE || extension == ".xls"

      nil
    end

    def spreadsheet_to_csv(file, format)
      spreadsheet = Roo::Spreadsheet.open(path_for(file), extension: format)
      sheet = first_non_empty_sheet(spreadsheet)
      raise Error, "Spreadsheet is empty" unless sheet

      header = normalize_row(sheet.row(1))
      raise Error, "Spreadsheet has no header row" if row_blank?(header)

      data_rows = (2..sheet.last_row.to_i).filter_map do |row_index|
        row = normalize_row(sheet.row(row_index))
        row_blank?(row) ? nil : row
      end
      raise Error, "Spreadsheet has no data rows" if data_rows.empty?

      CSV.generate do |csv|
        csv << header
        data_rows.each { |row| csv << row }
      end
    rescue Roo::Error, Zip::Error => e
      raise Error, "Invalid spreadsheet format: #{e.message}"
    end

    def first_non_empty_sheet(spreadsheet)
      spreadsheet.sheets.each do |name|
        sheet = spreadsheet.sheet(name)
        next if sheet.last_row.to_i < 1

        return sheet if (1..sheet.last_row.to_i).any? { |row| !row_blank?(sheet.row(row)) }
      end

      nil
    end

    def normalize_row(row)
      Array(row).map { |cell| normalize_cell(cell) }
    end

    def normalize_cell(cell)
      case cell
      when nil
        nil
      when Date, DateTime, Time
        cell.to_date.iso8601
      else
        cell.to_s.strip
      end
    end

    def row_blank?(row)
      row.all? { |cell| cell.to_s.strip.empty? }
    end

    def path_for(file)
      if file.respond_to?(:path)
        file.path
      elsif file.respond_to?(:tempfile)
        file.tempfile.path
      else
        raise Error, "Unable to read uploaded file"
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

require "test_helper"
require "tempfile"

class ImportFileNormalizerServiceTest < ActiveSupport::TestCase
  XLSX_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze

  test "reads CSV content unchanged" do
    csv_content = "Date,Description,Amount\n2026-01-15,Coffee,5.50\n"
    file = StringIO.new(csv_content)

    result = ImportFileNormalizerService.read_content(
      file,
      content_type: "text/csv",
      filename: "statement.csv"
    )

    assert_equal csv_content, result
  end

  test "converts xlsx first non-empty sheet to csv text" do
    spreadsheet = FakeSpreadsheet.new(
      "Empty" => FakeSheet.new([ [] ]),
      "Transactions" => FakeSheet.new(
        [
          [ "Date", "Description", "Amount" ],
          [ Date.new(2026, 1, 15), "Coffee", 5.50 ],
          [ nil, nil, nil ]
        ]
      )
    )

    Tempfile.create([ "import", ".xlsx" ]) do |file|
      file.write("placeholder")
      file.rewind

      with_stubbed_roo_open(spreadsheet) do
        result = ImportFileNormalizerService.read_content(
          file,
          content_type: XLSX_TYPE,
          filename: "statement.xlsx"
        )

        rows = CSV.parse(result)
        assert_equal [ "Date", "Description", "Amount" ], rows.first
        assert_equal [ "2026-01-15", "Coffee", "5.5" ], rows.second
      end
    end
  end

  test "raises error when spreadsheet has no data rows" do
    spreadsheet = FakeSpreadsheet.new(
      "Sheet1" => FakeSheet.new([ [ "Date", "Description", "Amount" ] ])
    )

    Tempfile.create([ "import", ".xlsx" ]) do |file|
      file.write("placeholder")
      file.rewind

      with_stubbed_roo_open(spreadsheet) do
        error = assert_raises ImportFileNormalizerService::Error do
          ImportFileNormalizerService.read_content(
            file,
            content_type: XLSX_TYPE,
            filename: "statement.xlsx"
          )
        end

        assert_match(/no data rows/i, error.message)
      end
    end
  end

  private

  class FakeSpreadsheet
    def initialize(sheets)
      @sheets = sheets
    end

    def sheets
      @sheets.keys
    end

    def sheet(name)
      @sheets.fetch(name)
    end
  end

  class FakeSheet
    def initialize(rows)
      @rows = rows
    end

    def last_row
      @rows.length
    end

    def row(index)
      @rows[index - 1] || []
    end
  end

  def with_stubbed_roo_open(spreadsheet)
    original_open = Roo::Spreadsheet.method(:open)
    Roo::Spreadsheet.define_singleton_method(:open) { |*_args, **_kwargs| spreadsheet }
    yield
  ensure
    Roo::Spreadsheet.define_singleton_method(:open, original_open)
  end
end

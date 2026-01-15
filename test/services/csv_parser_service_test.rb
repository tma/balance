require "test_helper"
require "stringio"

class CsvParserServiceTest < ActiveSupport::TestCase
  test "extracts text from CSV content" do
    csv_content = "Date,Description,Amount\n2026-01-15,Coffee,5.50\n2026-01-16,Lunch,12.00"
    file = StringIO.new(csv_content)

    result = CsvParserService.extract_text(file)

    assert_includes result, "Date,Description,Amount"
    assert_includes result, "Coffee"
    assert_includes result, "12.00"
  end

  test "raises error for empty file" do
    file = StringIO.new("")

    assert_raises CsvParserService::Error do
      CsvParserService.extract_text(file)
    end
  end

  test "truncates very long files" do
    # Create a CSV with more than 500 lines
    lines = [ "Header" ]
    600.times { |i| lines << "Line #{i},Data,#{i}.00" }
    file = StringIO.new(lines.join("\n"))

    result = CsvParserService.extract_text(file)

    assert_includes result, "truncated"
    assert_includes result, "Header"
  end

  test "handles whitespace-only content as empty" do
    file = StringIO.new("   \n\n   ")

    assert_raises CsvParserService::Error do
      CsvParserService.extract_text(file)
    end
  end
end

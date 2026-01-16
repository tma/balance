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

  test "truncates very long files in extract_text" do
    # Create a CSV with more than 500 lines
    lines = [ "Header\n" ]
    600.times { |i| lines << "Line #{i},Data,#{i}.00\n" }
    file = StringIO.new(lines.join)

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

  test "extract_chunks returns array of chunks" do
    csv_content = "Date,Description,Amount\n2026-01-15,Coffee,5.50\n2026-01-16,Lunch,12.00"
    file = StringIO.new(csv_content)

    result = CsvParserService.extract_chunks(file)

    assert_kind_of Array, result
    assert_equal 1, result.size
    assert_includes result.first, "Date,Description,Amount"
    assert_includes result.first, "Coffee"
  end

  test "extract_chunks splits large files into chunks with headers" do
    # Create a CSV with more than CHUNK_SIZE (50) rows
    lines = [ "Date,Description,Amount\n" ]
    120.times { |i| lines << "2026-01-#{(i % 28) + 1},Item #{i},#{i}.00\n" }
    file = StringIO.new(lines.join)

    result = CsvParserService.extract_chunks(file)

    assert_kind_of Array, result
    assert_equal 3, result.size # 120 rows / 50 per chunk = 3 chunks

    # Each chunk should start with the header
    result.each do |chunk|
      assert chunk.start_with?("Date,Description,Amount"), "Each chunk should include the header"
    end
  end

  test "extract_chunks handles single line CSV" do
    csv_content = "Date,Description,Amount"
    file = StringIO.new(csv_content)

    result = CsvParserService.extract_chunks(file)

    assert_equal 1, result.size
    assert_equal csv_content, result.first
  end

  test "extract_chunks raises error for empty file" do
    file = StringIO.new("")

    assert_raises CsvParserService::Error do
      CsvParserService.extract_chunks(file)
    end
  end
end

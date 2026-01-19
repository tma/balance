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
    # Create a CSV with more than CHUNK_SIZE (20) rows
    lines = [ "Date,Description,Amount\n" ]
    60.times { |i| lines << "2026-01-#{(i % 28) + 1},Item #{i},#{i}.00\n" }
    file = StringIO.new(lines.join)

    result = CsvParserService.extract_chunks(file)

    assert_kind_of Array, result
    assert_equal 3, result.size # 60 rows / 20 per chunk = 3 chunks

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

  test "handles ISO-8859-1 encoded content" do
    # Create content with ISO-8859-1 characters (e.g., German umlauts)
    # "Café" and "Zürich" in ISO-8859-1
    iso_content = "Date,Description,Amount\n2026-01-15,Caf\xE9,5.50\n2026-01-16,Z\xFCrich,12.00"
    iso_content.force_encoding("ASCII-8BIT") # Simulate binary read

    file = StringIO.new(iso_content)
    result = CsvParserService.extract_text(file)

    assert result.valid_encoding?
    assert_equal "UTF-8", result.encoding.name
    assert_includes result, "Date,Description,Amount"
  end

  test "handles UTF-8 content read as binary" do
    # UTF-8 content with special characters
    utf8_content = "Date,Description,Amount\n2026-01-15,Café,5.50\n2026-01-16,Zürich,12.00"
    binary_content = utf8_content.dup.force_encoding("ASCII-8BIT")

    file = StringIO.new(binary_content)
    result = CsvParserService.extract_text(file)

    assert result.valid_encoding?
    assert_equal "UTF-8", result.encoding.name
    assert_includes result, "Café"
    assert_includes result, "Zürich"
  end
end

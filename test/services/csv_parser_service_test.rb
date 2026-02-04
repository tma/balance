require "test_helper"
require "stringio"

class CsvParserServiceTest < ActiveSupport::TestCase
  test "reads content from CSV file" do
    csv_content = "Date,Description,Amount\n2026-01-15,Coffee,5.50\n2026-01-16,Lunch,12.00"
    file = StringIO.new(csv_content)

    result = CsvParserService.read_content(file)

    assert_includes result, "Date,Description,Amount"
    assert_includes result, "Coffee"
    assert_includes result, "12.00"
  end

  test "raises error for empty file" do
    file = StringIO.new("")

    assert_raises CsvParserService::Error do
      CsvParserService.read_content(file)
    end
  end

  test "handles whitespace-only content as empty" do
    file = StringIO.new("   \n\n   ")

    assert_raises CsvParserService::Error do
      CsvParserService.read_content(file)
    end
  end

  test "handles ISO-8859-1 encoded content" do
    # Create content with ISO-8859-1 characters (e.g., German umlauts)
    iso_content = +"Date,Description,Amount\n2026-01-15,Caf\xE9,5.50\n2026-01-16,Z\xFCrich,12.00"
    iso_content.force_encoding("ASCII-8BIT")

    file = StringIO.new(iso_content)
    result = CsvParserService.read_content(file)

    assert result.valid_encoding?
    assert_equal "UTF-8", result.encoding.name
    assert_includes result, "Date,Description,Amount"
  end

  test "handles UTF-8 content read as binary" do
    utf8_content = "Date,Description,Amount\n2026-01-15,Café,5.50\n2026-01-16,Zürich,12.00"
    binary_content = utf8_content.dup.force_encoding("ASCII-8BIT")

    file = StringIO.new(binary_content)
    result = CsvParserService.read_content(file)

    assert result.valid_encoding?
    assert_equal "UTF-8", result.encoding.name
    assert_includes result, "Café"
    assert_includes result, "Zürich"
  end

  test "strips UTF-8 BOM from content" do
    # UTF-8 BOM is \xEF\xBB\xBF
    bom_content = "\xEF\xBB\xBFDate,Description,Amount\n2026-01-15,Coffee,5.50"
    file = StringIO.new(bom_content)

    result = CsvParserService.read_content(file)

    assert result.start_with?("Date,"), "BOM should be stripped from start of content"
    assert_not result.start_with?("\xEF\xBB\xBF"), "BOM bytes should not be present"
  end
end

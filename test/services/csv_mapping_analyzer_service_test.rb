require "test_helper"

class CsvMappingAnalyzerServiceTest < ActiveSupport::TestCase
  # These tests require Ollama to be running, so we'll skip them in CI
  # and use mocked responses for unit testing

  test "raises error for empty CSV" do
    assert_raises CsvMappingAnalyzerService::AnalysisError do
      CsvMappingAnalyzerService.analyze("")
    end
  end

  test "raises error for CSV with only header" do
    assert_raises CsvMappingAnalyzerService::AnalysisError do
      CsvMappingAnalyzerService.analyze("Date,Description,Amount")
    end
  end

  test "normalizes date format strings" do
    # Test the private method via send
    service = CsvMappingAnalyzerService

    assert_equal "%Y-%m-%d", service.send(:normalize_date_format, "YYYY-MM-DD")
    assert_equal "%d.%m.%Y", service.send(:normalize_date_format, "DD.MM.YYYY")
    assert_equal "%m/%d/%Y", service.send(:normalize_date_format, "MM/DD/YYYY")
    assert_equal "%d.%m.%y", service.send(:normalize_date_format, "DD.MM.YY")
  end

  test "parses header columns correctly" do
    service = CsvMappingAnalyzerService

    # Simple header
    assert_equal [ "Date", "Description", "Amount" ], service.send(:parse_header_columns, "Date,Description,Amount")

    # Quoted header
    assert_equal [ "Date", "Description", "Amount" ], service.send(:parse_header_columns, '"Date","Description","Amount"')

    # Header with spaces
    assert_equal [ "Date", "Description", "Amount" ], service.send(:parse_header_columns, "Date , Description , Amount")
  end

  test "find_column matches case-insensitively and returns actual column name" do
    service = CsvMappingAnalyzerService
    columns = [ "datum", "BESCHREIBUNG", "Betrag" ]

    # Exact match
    assert_equal "Betrag", service.send(:find_column, columns, "Betrag", "Amount")

    # Case-insensitive match returns actual column name
    assert_equal "datum", service.send(:find_column, columns, "Datum", "Date")
    assert_equal "BESCHREIBUNG", service.send(:find_column, columns, "Beschreibung", "Description")

    # Not found raises error with available columns listed
    error = assert_raises CsvMappingAnalyzerService::AnalysisError do
      service.send(:find_column, columns, "NotFound", "Test")
    end
    assert_includes error.message, "NotFound"
    assert_includes error.message, "Available:"
  end

  test "detect_delimiter identifies semicolon delimiter" do
    service = CsvMappingAnalyzerService

    # Semicolon-delimited (European)
    assert_equal ";", service.send(:detect_delimiter, "Datum;Beschreibung;Betrag")
    # Comma-delimited (Standard)
    assert_equal ",", service.send(:detect_delimiter, "Date,Description,Amount")
    # Tab-delimited
    assert_equal "\t", service.send(:detect_delimiter, "Date\tDescription\tAmount")
    # Mixed - semicolon preferred if equal or more
    assert_equal ";", service.send(:detect_delimiter, "A;B,C;D")
  end

  test "parses semicolon-delimited headers correctly" do
    service = CsvMappingAnalyzerService

    columns = service.send(:parse_header_columns, '"Datum";"Buchungstext";"Betrag"')
    assert_equal [ "Datum", "Buchungstext", "Betrag" ], columns
  end

  # Integration test - only runs if Ollama is available
  test "analyzes simple CSV structure" do
    skip "Ollama not available" unless OllamaService.available?

    content = <<~CSV
      Date,Description,Amount
      2026-01-15,Coffee Shop,-5.50
      2026-01-16,Salary,3000.00
      2026-01-17,Grocery Store,-45.00
    CSV

    mapping = CsvMappingAnalyzerService.analyze(content)

    assert_equal "Date", mapping[:date_column]
    assert_equal "Description", mapping[:description_column]
    assert_equal "single", mapping[:amount_type]
    assert_equal "Amount", mapping[:amount_column]
    assert_includes [ "%Y-%m-%d", "%y-%m-%d" ], mapping[:date_format]
  end

  test "analyzes CSV with split debit/credit columns" do
    skip "Ollama not available" unless OllamaService.available?

    content = <<~CSV
      Transaction Date,Merchant,Debit,Credit
      2026-01-15,Coffee Shop,5.50,
      2026-01-16,Salary,,3000.00
      2026-01-17,Grocery Store,45.00,
    CSV

    mapping = CsvMappingAnalyzerService.analyze(content)

    assert_equal "Transaction Date", mapping[:date_column]
    assert_equal "Merchant", mapping[:description_column]
    assert_equal "split", mapping[:amount_type]
    assert_equal "Debit", mapping[:debit_column]
    assert_equal "Credit", mapping[:credit_column]
  end

  test "analyzes European format CSV" do
    skip "Ollama not available" unless OllamaService.available?

    content = <<~CSV
      Datum,Beschreibung,Betrag
      15.01.2026,Kaffee,-5.50
      16.01.2026,Gehalt,3000.00
    CSV

    mapping = CsvMappingAnalyzerService.analyze(content)

    assert_equal "Datum", mapping[:date_column]
    assert_equal "Beschreibung", mapping[:description_column]
    assert_equal "Betrag", mapping[:amount_column]
    assert_includes [ "%d.%m.%Y", "%d.%m.%y" ], mapping[:date_format]
  end
end

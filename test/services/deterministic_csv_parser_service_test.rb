require "test_helper"

class DeterministicCsvParserServiceTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:checking_account)
  end

  test "parses CSV with single amount column (negative = expense)" do
    content = <<~CSV
      Date,Description,Amount
      2026-01-15,Coffee Shop,-5.50
      2026-01-16,Salary,3000.00
    CSV

    mapping = {
      date_column: "Date",
      description_column: "Description",
      amount_type: "single",
      amount_column: "Amount",
      date_format: "%Y-%m-%d",
      amount_format: "plain"
    }

    parser = DeterministicCsvParserService.new(content, mapping, @account)
    transactions = parser.parse

    assert_equal 2, transactions.size

    assert_equal Date.new(2026, 1, 15), transactions[0][:date]
    assert_equal "Coffee Shop", transactions[0][:description]
    assert_equal 5.50, transactions[0][:amount]
    assert_equal "expense", transactions[0][:transaction_type]

    assert_equal Date.new(2026, 1, 16), transactions[1][:date]
    assert_equal "Salary", transactions[1][:description]
    assert_equal 3000.00, transactions[1][:amount]
    assert_equal "income", transactions[1][:transaction_type]
  end

  test "parses CSV with split debit/credit columns" do
    content = <<~CSV
      Date,Description,Debit,Credit
      2026-01-15,Coffee Shop,5.50,
      2026-01-16,Salary,,3000.00
    CSV

    mapping = {
      date_column: "Date",
      description_column: "Description",
      amount_type: "split",
      debit_column: "Debit",
      credit_column: "Credit",
      date_format: "%Y-%m-%d",
      amount_format: "plain"
    }

    parser = DeterministicCsvParserService.new(content, mapping, @account)
    transactions = parser.parse

    assert_equal 2, transactions.size

    assert_equal "expense", transactions[0][:transaction_type]
    assert_equal 5.50, transactions[0][:amount]

    assert_equal "income", transactions[1][:transaction_type]
    assert_equal 3000.00, transactions[1][:amount]
  end

  test "parses European date format DD.MM.YYYY" do
    content = <<~CSV
      Datum,Beschreibung,Betrag
      15.01.2026,Kaffee,-5.50
    CSV

    mapping = {
      date_column: "Datum",
      description_column: "Beschreibung",
      amount_type: "single",
      amount_column: "Betrag",
      date_format: "%d.%m.%Y",
      amount_format: "plain"
    }

    parser = DeterministicCsvParserService.new(content, mapping, @account)
    transactions = parser.parse

    assert_equal 1, transactions.size
    assert_equal Date.new(2026, 1, 15), transactions[0][:date]
  end

  test "parses European amount format with comma decimal" do
    content = <<~CSV
      Date,Description,Amount
      2026-01-15,Purchase,-1.234,56
    CSV

    mapping = {
      date_column: "Date",
      description_column: "Description",
      amount_type: "single",
      amount_column: "Amount",
      date_format: "%Y-%m-%d",
      amount_format: "eu"
    }

    # Need to handle the CSV parsing of EU format amounts which have commas
    # This is tricky because CSV uses comma as delimiter
    # In practice, EU format CSVs use semicolon delimiter or quote the amounts
    content_semicolon = <<~CSV
      Date;Description;Amount
      2026-01-15;Purchase;-1.234,56
    CSV

    # For this test, let's use a simpler EU format without thousands separator
    content_simple = <<~CSV
      Date,Description,Amount
      2026-01-15,Purchase,"-1234,56"
    CSV

    mapping_simple = {
      date_column: "Date",
      description_column: "Description",
      amount_type: "single",
      amount_column: "Amount",
      date_format: "%Y-%m-%d",
      amount_format: "eu"
    }

    parser = DeterministicCsvParserService.new(content_simple, mapping_simple, @account)
    transactions = parser.parse

    assert_equal 1, transactions.size
    assert_equal 1234.56, transactions[0][:amount]
    assert_equal "expense", transactions[0][:transaction_type]
  end

  test "strips currency symbols from amounts" do
    content = <<~CSV
      Date,Description,Amount
      2026-01-15,Coffee,$-5.50
      2026-01-16,Lunch,CHF -12.00
    CSV

    mapping = {
      date_column: "Date",
      description_column: "Description",
      amount_type: "single",
      amount_column: "Amount",
      date_format: "%Y-%m-%d",
      amount_format: "us"
    }

    parser = DeterministicCsvParserService.new(content, mapping, @account)
    transactions = parser.parse

    assert_equal 2, transactions.size
    assert_equal 5.50, transactions[0][:amount]
    assert_equal 12.00, transactions[1][:amount]
  end

  test "skips rows with blank descriptions" do
    content = <<~CSV
      Date,Description,Amount
      2026-01-15,Coffee,-5.50
      2026-01-16,,-10.00
      2026-01-17,Lunch,-12.00
    CSV

    mapping = {
      date_column: "Date",
      description_column: "Description",
      amount_type: "single",
      amount_column: "Amount",
      date_format: "%Y-%m-%d",
      amount_format: "plain"
    }

    parser = DeterministicCsvParserService.new(content, mapping, @account)
    transactions = parser.parse

    assert_equal 2, transactions.size
    assert_equal "Coffee", transactions[0][:description]
    assert_equal "Lunch", transactions[1][:description]
  end

  test "skips rows matching ignore patterns" do
    # Set up account with ignore patterns
    @account.update!(import_ignore_patterns: "Total\nBalance")

    content = <<~CSV
      Date,Description,Amount
      2026-01-15,Coffee,-5.50
      2026-01-16,Total,-100.00
      2026-01-17,Account Balance,5000.00
    CSV

    mapping = {
      date_column: "Date",
      description_column: "Description",
      amount_type: "single",
      amount_column: "Amount",
      date_format: "%Y-%m-%d",
      amount_format: "plain"
    }

    parser = DeterministicCsvParserService.new(content, mapping, @account)
    transactions = parser.parse

    assert_equal 1, transactions.size
    assert_equal "Coffee", transactions[0][:description]
  end

  test "handles fallback date formats" do
    content = <<~CSV
      Date,Description,Amount
      01/15/2026,Coffee,-5.50
    CSV

    mapping = {
      date_column: "Date",
      description_column: "Description",
      amount_type: "single",
      amount_column: "Amount",
      date_format: "%d.%m.%Y",  # Wrong format, should fallback
      amount_format: "plain"
    }

    parser = DeterministicCsvParserService.new(content, mapping, @account)
    transactions = parser.parse

    assert_equal 1, transactions.size
    assert_equal Date.new(2026, 1, 15), transactions[0][:date]
  end

  test "sets account_id on all transactions" do
    content = <<~CSV
      Date,Description,Amount
      2026-01-15,Coffee,-5.50
    CSV

    mapping = {
      date_column: "Date",
      description_column: "Description",
      amount_type: "single",
      amount_column: "Amount",
      date_format: "%Y-%m-%d",
      amount_format: "plain"
    }

    parser = DeterministicCsvParserService.new(content, mapping, @account)
    transactions = parser.parse

    assert_equal @account.id, transactions[0][:account_id]
  end

  test "returns empty array when no transactions can be parsed" do
    content = <<~CSV
      Date,Description,Amount
      invalid,,-
    CSV

    mapping = {
      date_column: "Date",
      description_column: "Description",
      amount_type: "single",
      amount_column: "Amount",
      date_format: "%Y-%m-%d",
      amount_format: "plain"
    }

    parser = DeterministicCsvParserService.new(content, mapping, @account)
    transactions = parser.parse

    # Parser skips invalid rows and returns empty array
    assert_equal [], transactions
  end
end

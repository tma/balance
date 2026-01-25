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

  test "inverts transaction types for credit card accounts with single amount column" do
    credit_account = accounts(:credit_card_account)

    content = <<~CSV
      Date,Description,Amount
      2026-01-15,Amazon Purchase,50.00
      2026-01-16,Payment Received,-200.00
    CSV

    mapping = {
      date_column: "Date",
      description_column: "Description",
      amount_type: "single",
      amount_column: "Amount",
      date_format: "%Y-%m-%d",
      amount_format: "plain"
    }

    parser = DeterministicCsvParserService.new(content, mapping, credit_account)
    transactions = parser.parse

    assert_equal 2, transactions.size

    # Positive amount on credit card = purchase = expense (inverted from income)
    assert_equal "expense", transactions[0][:transaction_type]
    assert_equal 50.00, transactions[0][:amount]

    # Negative amount on credit card = payment = income (inverted from expense)
    assert_equal "income", transactions[1][:transaction_type]
    assert_equal 200.00, transactions[1][:amount]
  end

  test "inverts transaction types for credit card accounts with split columns" do
    credit_account = accounts(:credit_card_account)

    content = <<~CSV
      Date,Description,Debit,Credit
      2026-01-15,Amazon Purchase,50.00,
      2026-01-16,Payment Received,,200.00
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

    parser = DeterministicCsvParserService.new(content, mapping, credit_account)
    transactions = parser.parse

    assert_equal 2, transactions.size

    # Debit on credit card = purchase = income (inverted from expense)
    assert_equal "income", transactions[0][:transaction_type]
    assert_equal 50.00, transactions[0][:amount]

    # Credit on credit card = payment = expense (inverted from income)
    assert_equal "expense", transactions[1][:transaction_type]
    assert_equal 200.00, transactions[1][:amount]
  end

  test "does not invert transaction types for normal accounts" do
    # checking_account has invert_amounts_on_import: false
    content = <<~CSV
      Date,Description,Amount
      2026-01-15,Coffee,-5.50
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
    assert_equal "expense", transactions[0][:transaction_type]
    assert_equal "income", transactions[1][:transaction_type]
  end

  test "parses semicolon-delimited CSV (European format)" do
    content = <<~CSV
      Datum;Buchungstext;Belastung CHF;Gutschrift CHF
      15.01.2026;Kaffee Haus;5,50;
      16.01.2026;Gehalt;;3000,00
    CSV

    mapping = {
      date_column: "Datum",
      description_column: "Buchungstext",
      amount_type: "split",
      debit_column: "Belastung CHF",
      credit_column: "Gutschrift CHF",
      date_format: "%d.%m.%Y",
      amount_format: "eu"
    }

    parser = DeterministicCsvParserService.new(content, mapping, @account)
    transactions = parser.parse

    assert_equal 2, transactions.size

    assert_equal Date.new(2026, 1, 15), transactions[0][:date]
    assert_equal "Kaffee Haus", transactions[0][:description]
    assert_equal 5.50, transactions[0][:amount]
    assert_equal "expense", transactions[0][:transaction_type]

    assert_equal Date.new(2026, 1, 16), transactions[1][:date]
    assert_equal "Gehalt", transactions[1][:description]
    assert_equal 3000.00, transactions[1][:amount]
    assert_equal "income", transactions[1][:transaction_type]
  end

  test "detect_delimiter identifies semicolon delimiter" do
    parser = DeterministicCsvParserService.new("", {}, @account)

    # Semicolon-delimited
    assert_equal ";", parser.send(:detect_delimiter, "Datum;Beschreibung;Betrag")
    # Comma-delimited
    assert_equal ",", parser.send(:detect_delimiter, "Date,Description,Amount")
    # Tab-delimited
    assert_equal "\t", parser.send(:detect_delimiter, "Date\tDescription\tAmount")
    # Mixed - semicolon should win if equal or more
    assert_equal ";", parser.send(:detect_delimiter, "A;B,C;D")
  end

  test "parses grouped transactions with header and detail rows" do
    content = File.read(Rails.root.join("test/fixtures/files/csv_samples/ch_grouped_transactions.csv"))

    # Note: NOT providing detail_amount_column or detail_description_column
    # The parser should auto-detect them
    mapping = {
      date_column: "Datum",
      description_column: "Buchungstext",
      description_secondary_column: "Zahlungszweck",
      amount_type: "split",
      debit_column: "Belastung CHF",
      credit_column: "Gutschrift CHF",
      date_format: "%d.%m.%Y",
      amount_format: "plain"
    }

    parser = DeterministicCsvParserService.new(content, mapping, @account)
    transactions = parser.parse

    # Summary rows should be excluded (their amounts equal the sum of their detail rows)
    # So we should NOT see "Sammelüberweisung - Monatliche Zahlungen" or "Sammelüberweisung - Kleinausgaben"
    sammel = transactions.find { |t| t[:description].include?("Sammelüberweisung") }
    assert_nil sammel, "Summary rows should be excluded when details sum to header amount"

    # Detail rows from first grouped transaction
    migros = transactions.find { |t| t[:description] == "Migros Supermarkt Einkauf" }
    assert_not_nil migros, "Should find Migros detail row (auto-detected)"
    assert_equal Date.new(2026, 1, 15), migros[:date]
    assert_equal 350.00, migros[:amount]
    assert_equal "expense", migros[:transaction_type]

    coop = transactions.find { |t| t[:description] == "Coop Pronto Tankstelle" }
    assert_not_nil coop, "Should find Coop detail row"
    assert_equal Date.new(2026, 1, 15), coop[:date]
    assert_equal 450.00, coop[:amount]

    # Regular transaction (salary) - should have both Buchungstext and Zahlungszweck
    salary = transactions.find { |t| t[:description].include?("Lohneingang") }
    assert_not_nil salary, "Should find salary"
    assert_equal Date.new(2026, 1, 20), salary[:date]
    assert_equal 6500.00, salary[:amount]
    assert_equal "income", salary[:transaction_type]
    assert_equal "Lohneingang - Gehalt Januar 2026", salary[:description], "Should combine Buchungstext and Zahlungszweck"

    # Detail rows from second grouped transaction
    denner = transactions.find { |t| t[:description] == "Denner Lebensmittel" }
    assert_not_nil denner, "Should find Denner detail row"
    assert_equal Date.new(2026, 1, 28), denner[:date]
    assert_equal 45.80, denner[:amount]

    manor = transactions.find { |t| t[:description] == "Manor Kleider" }
    assert_not_nil manor, "Should find Manor detail row"
    assert_equal Date.new(2026, 1, 28), manor[:date]

    # Verify we have the expected total count of detail rows
    detail_rows = transactions.select { |t|
      [ "Migros Supermarkt Einkauf", "Coop Pronto Tankstelle", "Swisscom Mobile Rechnung",
        "SBB Generalabonnement", "Denner Lebensmittel", "Manor Kleider", "Kino Pathé Tickets" ].include?(t[:description])
    }
    assert_equal 7, detail_rows.size, "Should have 7 detail rows total"

    # Total should be 11: 7 detail rows + 4 standalone transactions (salary, IKEA, rent, interest)
    assert_equal 11, transactions.size, "Should have 11 transactions (7 details + 4 standalone)"
  end
end

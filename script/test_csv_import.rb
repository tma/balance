#!/usr/bin/env ruby
# Script to test CSV import with synthetic data
# Run with: rails runner script/test_csv_import.rb

require "fileutils"

CSV_SAMPLES_DIR = Rails.root.join("test/fixtures/files/csv_samples")

def test_csv_file(filepath)
  filename = File.basename(filepath)
  puts "\n#{"=" * 60}"
  puts "Testing: #{filename}"
  puts "=" * 60

  content = File.read(filepath)
  puts "\nCSV Preview (first 5 lines):"
  puts content.lines.first(5).join
  puts "..."

  # Step 1: Analyze structure
  puts "\n[Step 1] Analyzing CSV structure with LLM..."
  begin
    mapping = CsvMappingAnalyzerService.analyze(content)
    puts "✓ Mapping detected:"
    mapping.each { |k, v| puts "    #{k}: #{v}" }
  rescue => e
    puts "✗ Analysis failed: #{e.message}"
    return { file: filename, status: :analysis_failed, error: e.message }
  end

  # Step 2: Parse with deterministic parser
  puts "\n[Step 2] Parsing all rows deterministically..."
  account = Account.first || Account.create!(
    name: "Test Account",
    account_type: AccountType.first || AccountType.create!(name: "checking"),
    balance: 0,
    currency: "USD"
  )

  begin
    parser = DeterministicCsvParserService.new(content, mapping, account)
    transactions = parser.parse
    puts "✓ Parsed #{transactions.size} transactions"

    if transactions.any?
      puts "\nSample transactions:"
      transactions.first(3).each do |txn|
        puts "    #{txn[:date]} | #{txn[:description].truncate(30)} | #{txn[:transaction_type]} | #{txn[:amount]}"
      end
    end
  rescue => e
    puts "✗ Parsing failed: #{e.message}"
    return { file: filename, status: :parse_failed, error: e.message }
  end

  # Validate results
  puts "\n[Step 3] Validating results..."
  csv_row_count = content.lines.drop(1).reject { |l| l.strip.empty? }.size
  
  issues = []
  issues << "Row count mismatch: expected ~#{csv_row_count}, got #{transactions.size}" if transactions.size < csv_row_count * 0.8

  transactions.each_with_index do |txn, i|
    issues << "Transaction #{i+1}: invalid date #{txn[:date]}" unless txn[:date].is_a?(Date)
    issues << "Transaction #{i+1}: invalid amount #{txn[:amount]}" unless txn[:amount].is_a?(Numeric) && txn[:amount] > 0
    issues << "Transaction #{i+1}: invalid type #{txn[:transaction_type]}" unless %w[income expense].include?(txn[:transaction_type])
  end

  if issues.empty?
    puts "✓ All validations passed!"
    { file: filename, status: :success, transactions: transactions.size, mapping: mapping }
  else
    puts "⚠ Validation issues:"
    issues.first(5).each { |i| puts "    - #{i}" }
    { file: filename, status: :validation_issues, issues: issues, transactions: transactions.size }
  end
end

# Main execution
puts "=" * 60
puts "CSV Import Test Suite"
puts "=" * 60

unless OllamaService.available?
  puts "\n✗ Ollama is not available. Please start Ollama first."
  exit 1
end

puts "✓ Ollama is available"

csv_files = Dir.glob(CSV_SAMPLES_DIR.join("*.csv")).sort
puts "Found #{csv_files.size} test CSV files\n"

results = csv_files.map { |f| test_csv_file(f) }

# Summary
puts "\n\n#{"=" * 60}"
puts "SUMMARY"
puts "=" * 60

success = results.count { |r| r[:status] == :success }
failed = results.count { |r| r[:status] != :success }

puts "\nTotal: #{results.size} files"
puts "✓ Success: #{success}"
puts "✗ Failed: #{failed}"

if failed > 0
  puts "\nFailed files:"
  results.select { |r| r[:status] != :success }.each do |r|
    puts "  - #{r[:file]}: #{r[:status]} - #{r[:error] || r[:issues]&.first}"
  end
end

puts "\nDetailed results:"
results.each do |r|
  status_icon = r[:status] == :success ? "✓" : "✗"
  puts "#{status_icon} #{r[:file]}: #{r[:status]} (#{r[:transactions] || 0} transactions)"
end

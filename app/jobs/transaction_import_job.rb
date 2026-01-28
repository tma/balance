require "csv"

class TransactionImportJob < ApplicationJob
  queue_as :default

  retry_on OllamaService::Error, wait: :polynomially_longer, attempts: 3

  def perform(import_id)
    import = Import.find(import_id)
    return unless import.pending?

    import.mark_processing!

    begin
      transactions = if import.csv?
        process_csv(import)
      else
        process_pdf(import)
      end

      transactions = DuplicateDetectionService.mark_duplicates(transactions)
      import.mark_completed!(transactions)

    rescue PdfParserService::Error, CsvParserService::Error => e
      import.mark_failed!("File parsing error: #{e.message}")
    rescue CsvMappingAnalyzerService::AnalysisError => e
      import.mark_failed!("CSV analysis error: #{e.message}")
    rescue DeterministicCsvParserService::ParseError => e
      import.mark_failed!("CSV parsing error: #{e.message}")
    rescue TransactionExtractorService::ExtractionError => e
      import.mark_failed!("Extraction error: #{e.message}")
    rescue OllamaService::Error => e
      import.mark_failed!("AI service error: #{e.message}")
    rescue StandardError => e
      import.mark_failed!("Unexpected error: #{e.message}")
      raise
    end
  end

  private

  def process_csv(import)
    Rails.logger.info "Import #{import.id}: Processing CSV"

    # Stage 1: Reading file (5%)
    import.update_progress!(5, 100, message: "Reading file...")
    content = with_temp_file(import, ".csv") do |temp_file|
      CsvParserService.read_content(temp_file)
    end

    # Stage 2: Analyzing format (10-25%)
    cached = import.account.cached_csv_mapping.present?
    import.update_progress!(10, 100, message: cached ? "Using saved format" : "Analyzing CSV format...")
    mapping = get_or_analyze_csv_mapping(content, import.account)
    import.update_progress!(25, 100, message: "Format detected")

    # Stage 3: Parsing transactions (25-40%)
    import.update_progress!(30, 100, message: "Parsing transactions...")
    parser = DeterministicCsvParserService.new(content, mapping, import.account)
    transactions = parser.parse
    Rails.logger.info "Import #{import.id}: Parsed #{transactions.size} transactions"

    # Stage 4: Categorizing (40-95%)
    categorize_transactions(transactions, import.account, import: import, base_progress: 40, progress_range: 55)

    # Stage 5: Detecting duplicates (95-100%)
    import.update_progress!(95, 100, message: "Checking for duplicates...")

    transactions
  end

  def get_or_analyze_csv_mapping(content, account)
    # Try cached mapping first
    cached = account.cached_csv_mapping
    if cached
      Rails.logger.info "Using cached CSV mapping for account #{account.id}"
      # Validate cached mapping still works with this CSV
      if mapping_valid_for_content?(cached, content)
        return cached
      else
        Rails.logger.info "Cached mapping invalid for this CSV, re-analyzing"
      end
    end

    # Analyze with LLM
    mapping = CsvMappingAnalyzerService.analyze(content)

    # Cache for future imports
    account.cache_csv_mapping!(mapping)
    Rails.logger.info "Cached CSV mapping for account #{account.id}"

    mapping
  end

  def mapping_valid_for_content?(mapping, content)
    headers = content.lines.first&.strip || ""
    columns = ::CSV.parse_line(headers).map(&:to_s).map(&:strip)

    # Check required columns exist
    return false unless columns.include?(mapping[:date_column])
    return false unless columns.include?(mapping[:description_column])

    if mapping[:amount_type] == "single"
      return false unless columns.include?(mapping[:amount_column])
    else
      return false unless columns.include?(mapping[:debit_column])
      return false unless columns.include?(mapping[:credit_column])
    end

    true
  rescue ::CSV::MalformedCSVError
    false
  end

  def process_pdf(import)
    Rails.logger.info "Import #{import.id}: Processing PDF"

    # Stage 1: Reading PDF (5%)
    import.update_progress!(5, 100, message: "Reading PDF...")
    chunks = with_temp_file(import, ".pdf") do |temp_file|
      PdfParserService.extract_pages(temp_file)
    end

    Rails.logger.info "Import #{import.id}: Extracted #{chunks.size} page(s)"
    import.update_progress!(10, 100, message: "Extracted #{chunks.size} page(s)")

    # Stage 2-4: Extracting transactions (10-90%)
    progress_callback = lambda do |current, total, extracted_count: nil, message: nil|
      # Map page progress to 10-90% range
      percent = 10 + ((current.to_f / total) * 80).round
      import.update_progress!(percent, 100, extracted_count: extracted_count, message: message)
    end

    extractor = TransactionExtractorService.new(chunks, import.account, on_progress: progress_callback)
    transactions = extractor.extract

    # Stage 5: Detecting duplicates (95%)
    import.update_progress!(95, 100, message: "Checking for duplicates...")

    transactions
  end

  def categorize_transactions(transactions, account, import: nil, base_progress: 0, progress_range: 100)
    return if transactions.empty?

    total_txns = transactions.size

    progress_callback = lambda do |current, total, message:|
      if import
        percent = base_progress + ((current.to_f / total) * progress_range).round
        import.update_progress!(percent, 100, message: "#{message} (#{current}/#{total})")
      end
    end

    service = CategoryMatchingService.new(transactions, on_progress: progress_callback)
    service.categorize

    categorized_count = transactions.count { |t| t[:category_id].present? }
    Rails.logger.info "Categorization complete: #{categorized_count}/#{total_txns} categorized"
  end

  def with_temp_file(import, extension)
    Tempfile.create([ "import", extension ]) do |temp_file|
      temp_file.binmode
      temp_file.write(import.file_data)
      temp_file.rewind
      yield temp_file
    end
  end
end

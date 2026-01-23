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

    content = with_temp_file(import, ".csv") do |temp_file|
      CsvParserService.read_content(temp_file)
    end

    # Step 1: Get mapping (try cache first, then LLM)
    cached = import.account.cached_csv_mapping.present?
    import.update_progress!(1, 2, message: cached ? "Using saved format" : "Detecting CSV format")
    mapping = get_or_analyze_csv_mapping(content, import.account)

    # Step 2: Parse all rows and categorize
    parser = DeterministicCsvParserService.new(content, mapping, import.account)
    transactions = parser.parse
    Rails.logger.info "Import #{import.id}: Parsed #{transactions.size} transactions"

    progress_callback = ->(current, total) {
      import.update_progress!(2, 2, extracted_count: transactions.size, message: "Categorizing #{current}/#{total}")
    }
    categorize_transactions(transactions, import.account, on_progress: progress_callback)

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
    columns = CSV.parse_line(headers).map(&:to_s).map(&:strip)

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
  rescue CSV::MalformedCSVError
    false
  end

  def process_pdf(import)
    Rails.logger.info "Import #{import.id}: Processing PDF"

    chunks = with_temp_file(import, ".pdf") do |temp_file|
      PdfParserService.extract_pages(temp_file)
    end

    Rails.logger.info "Import #{import.id}: Extracted #{chunks.size} page(s)"

    progress_callback = lambda do |current, total, extracted_count: nil, message: nil|
      import.update_progress!(current, total, extracted_count: extracted_count, message: message)
    end

    extractor = TransactionExtractorService.new(chunks, import.account, on_progress: progress_callback)
    extractor.extract
  end

  def categorize_transactions(transactions, account, on_progress: nil)
    return if transactions.empty?

    # Step 1: Rule-based categorization using match_patterns
    uncategorized = []
    transactions.each do |txn|
      category = Category.find_by_pattern(txn[:description], txn[:transaction_type])
      if category
        txn[:category_id] = category.id
        txn[:category_name] = category.name
      else
        uncategorized << txn
      end
    end

    categorized_count = transactions.size - uncategorized.size
    Rails.logger.info "Rule-based categorization: #{categorized_count}/#{transactions.size} matched"

    # Step 2: LLM categorization for remaining transactions
    if uncategorized.any?
      batch_size = TransactionExtractorService::CATEGORY_BATCH_SIZE
      total_batches = (uncategorized.size.to_f / batch_size).ceil

      extractor = TransactionExtractorService.new([], account)
      uncategorized.each_slice(batch_size).with_index do |batch, index|
        on_progress&.call(index + 1, total_batches)
        extractor.send(:categorize_batch, batch, Category.expense, Category.income)
      end
    end
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

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
    Rails.logger.info "Import #{import.id}: Processing CSV with two-step approach"

    content = with_temp_file(import, ".csv") do |temp_file|
      CsvParserService.read_content(temp_file)
    end

    # Step 1: LLM analyzes structure (headers + sample rows)
    import.update_progress!(1, 3, message: "Analyzing CSV structure")
    mapping = CsvMappingAnalyzerService.analyze(content)
    Rails.logger.info "Import #{import.id}: CSV mapping detected: #{mapping.inspect}"

    # Step 2: Deterministic parsing of all rows
    import.update_progress!(2, 3, message: "Parsing transactions")
    parser = DeterministicCsvParserService.new(content, mapping, import.account)
    transactions = parser.parse
    Rails.logger.info "Import #{import.id}: Parsed #{transactions.size} transactions"

    # Step 3: Categorize using LLM
    import.update_progress!(3, 3, extracted_count: transactions.size, message: "Categorizing transactions")
    categorize_transactions(transactions, import.account)

    transactions
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

  def categorize_transactions(transactions, account)
    return if transactions.empty?

    # Reuse the categorization logic from TransactionExtractorService
    extractor = TransactionExtractorService.new([], account)
    extractor.categorize_transactions(transactions)
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

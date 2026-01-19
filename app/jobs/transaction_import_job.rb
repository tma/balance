class TransactionImportJob < ApplicationJob
  queue_as :default

  # Retry on transient failures
  retry_on OllamaService::Error, wait: :polynomially_longer, attempts: 3

  def perform(import_id)
    import = Import.find(import_id)

    # Skip if already processed
    return unless import.pending?

    import.mark_processing!

    begin
      # Parse file into chunks based on content type
      chunks = extract_chunks_from_import(import)

      Rails.logger.info "Import #{import_id}: Processing #{chunks.size} chunk(s)"

      # Progress callback to update import status
      progress_callback = lambda do |current, total, extracted_count: nil, message: nil|
        import.update_progress!(current, total, extracted_count: extracted_count, message: message)
      end

      # Extract transactions using Ollama (processes all chunks)
      file_type = import.pdf? ? :pdf : :csv
      extractor = TransactionExtractorService.new(chunks, import.account, file_type: file_type, on_progress: progress_callback)
      transactions = extractor.extract

      # Mark duplicates
      transactions = DuplicateDetectionService.mark_duplicates(transactions)

      # Store extracted data for user review
      import.mark_completed!(transactions)

    rescue PdfParserService::Error, CsvParserService::Error => e
      import.mark_failed!("File parsing error: #{e.message}")
    rescue TransactionExtractorService::ExtractionError => e
      import.mark_failed!("Extraction error: #{e.message}")
    rescue OllamaService::Error => e
      import.mark_failed!("AI service error: #{e.message}")
    rescue StandardError => e
      import.mark_failed!("Unexpected error: #{e.message}")
      raise # Re-raise for job retry logic
    end
  end

  private

  def extract_chunks_from_import(import)
    # Create a temporary file from the stored binary data
    Tempfile.create([ "import", extension_for(import) ]) do |temp_file|
      temp_file.binmode
      temp_file.write(import.file_data)
      temp_file.rewind

      if import.pdf?
        PdfParserService.extract_pages(temp_file)
      else
        CsvParserService.extract_chunks(temp_file)
      end
    end
  end

  def extension_for(import)
    import.pdf? ? ".pdf" : ".csv"
  end
end

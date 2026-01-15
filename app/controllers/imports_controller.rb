class ImportsController < ApplicationController
  def new
    @accounts = Account.order(:name)
  end

  def preview
    @account = Account.find(params[:account_id])
    file = params[:file]

    unless file.present?
      redirect_to new_import_path, alert: "Please select a file to import."
      return
    end

    # Extract text based on file type
    begin
      @raw_text = extract_text_from_file(file)
    rescue PdfParserService::Error, CsvParserService::Error => e
      redirect_to new_import_path, alert: e.message
      return
    end

    # Try to extract transactions using Ollama
    begin
      extractor = TransactionExtractorService.new(@raw_text, @account)
      @transactions = extractor.extract
      @transactions = DuplicateDetectionService.mark_duplicates(@transactions)
      @extraction_successful = true
    rescue TransactionExtractorService::ExtractionError, OllamaService::Error => e
      @extraction_error = e.message
      @extraction_successful = false
      @transactions = []
    end

    # For category dropdowns in the preview
    @expense_categories = Category.expense.order(:name)
    @income_categories = Category.income.order(:name)

    # Store raw text and account in session for manual fallback
    session[:import_raw_text] = @raw_text
    session[:import_account_id] = @account.id
  end

  def create
    @account = Account.find(params[:account_id])
    transactions_data = params[:transactions]&.values || []

    imported_count = 0
    errors = []

    transactions_data.each do |txn_data|
      # Skip unchecked transactions
      next unless txn_data[:selected] == "1"

      transaction = Transaction.new(
        account_id: @account.id,
        category_id: txn_data[:category_id],
        amount: txn_data[:amount].to_f,
        transaction_type: txn_data[:transaction_type],
        date: txn_data[:date],
        description: txn_data[:description],
        duplicate_hash: txn_data[:duplicate_hash]
      )

      if transaction.save
        imported_count += 1
      else
        errors << "#{txn_data[:description]}: #{transaction.errors.full_messages.join(', ')}"
      end
    end

    # Clear session data
    session.delete(:import_raw_text)
    session.delete(:import_account_id)

    if errors.any?
      flash[:alert] = "Imported #{imported_count} transactions. #{errors.size} failed: #{errors.first(3).join('; ')}"
    else
      flash[:notice] = "Successfully imported #{imported_count} transactions."
    end

    redirect_to transactions_path
  end

  private

  def extract_text_from_file(file)
    content_type = file.content_type
    filename = file.original_filename.downcase

    if content_type == "application/pdf" || filename.end_with?(".pdf")
      PdfParserService.extract_text(file)
    elsif content_type == "text/csv" || filename.end_with?(".csv")
      CsvParserService.extract_text(file)
    else
      # Try to read as plain text
      CsvParserService.extract_text(file)
    end
  end
end

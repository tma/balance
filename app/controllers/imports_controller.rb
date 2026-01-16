class ImportsController < ApplicationController
  before_action :set_import, only: %i[show confirm status]

  def index
    @imports = Import.recent.includes(:account).limit(20)
  end

  def new
    @accounts = Account.order(:name)
  end

  def show
    if @import.completed?
      @transactions = @import.extracted_transactions
      @expense_categories = Category.expense.order(:name)
      @income_categories = Category.income.order(:name)
    end
  end

  # Returns just the progress/status partial for Turbo Frame updates
  def status
    render partial: "imports/status", locals: { import: @import }, formats: [:html], layout: false
  end

  # Create the import record and enqueue the job
  def create
    @account = Account.find(params[:account_id])
    file = params[:file]

    unless file.present?
      redirect_to new_import_path, alert: "Please select a file to import."
      return
    end

    # Create import record with file data
    @import = Import.new(
      account: @account,
      original_filename: file.original_filename,
      file_content_type: determine_content_type(file),
      file_data: file.read
    )

    if @import.save
      # Enqueue the background job
      TransactionImportJob.perform_later(@import.id)
      redirect_to import_path(@import), notice: "Import started. Processing your file..."
    else
      redirect_to new_import_path, alert: "Failed to create import: #{@import.errors.full_messages.join(', ')}"
    end
  end

  # Actually create transactions from the extracted data
  def confirm
    unless @import.completed?
      redirect_to import_path(@import), alert: "Import is not ready for confirmation."
      return
    end

    transactions_data = params[:transactions]&.values || []
    imported_count = 0
    errors = []

    transactions_data.each do |txn_data|
      # Skip unchecked transactions
      next unless txn_data[:selected] == "1"

      transaction = Transaction.new(
        account_id: @import.account_id,
        import_id: @import.id,
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

    # Update import with final count
    @import.update!(transactions_count: imported_count)

    if errors.any?
      flash[:alert] = "Imported #{imported_count} transactions. #{errors.size} failed: #{errors.first(3).join('; ')}"
    else
      flash[:notice] = "Successfully imported #{imported_count} transactions."
    end

    redirect_to transactions_path
  end

  private

  def set_import
    @import = Import.find(params[:id])
  end

  def determine_content_type(file)
    content_type = file.content_type
    filename = file.original_filename.downcase

    if content_type == "application/pdf" || filename.end_with?(".pdf")
      "application/pdf"
    elsif content_type == "text/csv" || filename.end_with?(".csv")
      "text/csv"
    else
      "text/plain"
    end
  end
end

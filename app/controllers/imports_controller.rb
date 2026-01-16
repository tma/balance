class ImportsController < ApplicationController
  before_action :set_import, only: %i[show confirm reprocess status destroy]

  def index
    # Determine current year from params or default to current year
    @current_year = if params[:year].present?
      params[:year].to_i
    else
      Date.current.year
    end

    # Only show "finalized" imports: done (reviewed and imported) or failed
    # Pending, processing, and completed (ready-for-review) imports are shown on the Import (new) page
    all_imports = Import.recent.includes(:account).select do |import|
      import.failed? || import.done?
    end

    # Filter by year based on transaction_month or created_at
    imports = all_imports.select do |import|
      if import.transaction_month
        import.transaction_month.year == @current_year
      else
        import.created_at.year == @current_year
      end
    end

    # Group imports by transaction month
    @imports_by_month = imports.group_by(&:transaction_month)

    # Sort months descending (most recent first), with nil (ungrouped) at the end
    @sorted_months = @imports_by_month.keys.compact.sort.reverse
    @has_ungrouped = @imports_by_month.key?(nil)

    # Determine available years for navigation
    @available_years = all_imports.map do |import|
      import.transaction_month&.year || import.created_at.year
    end.uniq.sort.reverse
  end

  def new
    @accounts = Account.order(:name)
    # Load imports that need attention:
    # - pending/processing (in progress)
    # - completed (ready for human review)
    # - failed (can be deleted)
    @pending_imports = Import.includes(:account).recent.limit(20).select do |import|
      import.pending? || import.processing? || import.failed? || import.completed?
    end
  end

  def show
    if @import.completed?
      @transactions = @import.extracted_transactions.sort_by { |t| t[:date] }
      @expense_categories = Category.expense.order(:name)
      @income_categories = Category.income.order(:name)
    elsif @import.done?
      @imported_transactions = @import.transactions.includes(:category).order(:date)
    end
  end

  # Returns just the progress/status partial for Turbo Frame updates
  def status
    render partial: "imports/status", locals: { import: @import }, formats: [ :html ], layout: false
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

    # Update import with count, optionally mark as done
    if params[:mark_as_done] == "1"
      @import.update!(transactions_count: imported_count, status: "done")
    else
      @import.update!(transactions_count: @import.transactions_count + imported_count)
    end

    if errors.any?
      flash[:alert] = "Imported #{imported_count} transactions. #{errors.size} failed: #{errors.first(3).join('; ')}"
    else
      flash[:notice] = "Successfully imported #{imported_count} transactions."
    end

    redirect_to transactions_path
  end

  def destroy
    unless @import.completed? || @import.failed? || @import.done?
      redirect_to import_path(@import), alert: "Cannot delete an import that is still processing."
      return
    end

    @import.destroy
    redirect_to new_import_path, notice: "Import deleted."
  end

  def reprocess
    unless @import.failed? || @import.completed?
      redirect_to import_path(@import), alert: "Only failed or ready-for-review imports can be reprocessed."
      return
    end

    # Reset the import status and clear error
    @import.update!(status: "pending", error_message: nil, extracted_data: "[]")

    # Enqueue the background job again
    TransactionImportJob.perform_later(@import.id)

    redirect_to import_path(@import), notice: "Reprocessing import..."
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

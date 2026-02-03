class ImportsController < ApplicationController
  before_action :set_import, only: %i[show save confirm reprocess status destroy]

  def index
    # Imports needing attention (completed ready for review, or failed)
    @needs_attention = Import.needs_attention.includes(:account).recent

    # Only show "finalized" imports: done (reviewed and imported) or failed
    # Pending, processing, and completed (ready-for-review) imports are shown on the Import (new) page
    all_imports = Import.recent.includes(:account, :transactions).select do |import|
      import.failed? || import.done?
    end

    # Account filter mode: show all imports for a specific account, sorted by date
    if params[:account_id].present?
      @filter_account = Account.find(params[:account_id])
      imports = all_imports.select { |i| i.account_id == @filter_account.id }
        .sort_by { |i| i.transaction_month || i.created_at.to_date }.reverse

      @imports_by_month = imports.group_by(&:transaction_month)
      @sorted_months = @imports_by_month.keys.compact.sort.reverse
      @has_ungrouped = @imports_by_month.key?(nil)
      @available_years = []
      @current_year = nil
    else
      # Year filter mode (default)
      @current_year = params[:year].present? ? params[:year].to_i : Date.current.year

      imports = all_imports.select do |import|
        if import.transaction_month
          import.transaction_month.year == @current_year
        else
          import.created_at.year == @current_year
        end
      end

      @imports_by_month = imports.group_by(&:transaction_month)
      @sorted_months = @imports_by_month.keys.compact.sort.reverse
      @has_ungrouped = @imports_by_month.key?(nil)

      @available_years = all_imports.map do |import|
        import.transaction_month&.year || import.created_at.year
      end.uniq.sort.reverse
    end

    # Coverage analysis for accounts with expected_transaction_frequency set
    accounts_with_frequency = Account.active
      .where.not(expected_transaction_frequency: nil)

    @account_coverage = accounts_with_frequency.filter_map(&:coverage_analysis)
      .sort_by { |c| c[:complete?] ? 1 : 0 } # Show incomplete first

    # Accounts for filter dropdown
    @filter_accounts = Account.active.order(:name)
  end

  def new
    @accounts = Account.order(:name)
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

  # Save the current form state without importing
  def save
    unless @import.completed?
      redirect_to import_path(@import), alert: "Import is not ready for editing."
      return
    end

    transactions_data = params[:transactions]&.values || []

    updated_transactions = transactions_data.map do |txn_params|
      {
        date: txn_params[:date],
        description: txn_params[:description],
        amount: txn_params[:amount],
        transaction_type: txn_params[:transaction_type],
        category_id: txn_params[:category_id].present? ? txn_params[:category_id].to_i : nil,
        duplicate_hash: txn_params[:duplicate_hash],
        is_duplicate: txn_params[:is_duplicate] == "1",
        is_ignored: txn_params[:is_ignored] == "1",
        selected: txn_params[:selected] == "1"
      }
    end

    @import.extracted_transactions = updated_transactions

    if @import.save
      redirect_to import_path(@import), notice: "Changes saved."
    else
      redirect_to import_path(@import), alert: "Failed to save changes."
    end
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

    # Mark import as done if requested
    if params[:mark_as_done] == "1"
      @import.update!(status: "done")
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

    # Clear cached CSV mapping to force re-analysis
    @import.account.update!(csv_column_mapping: nil) if @import.file_content_type == "text/csv"

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

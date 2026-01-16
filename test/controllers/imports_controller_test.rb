require "test_helper"

class ImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:checking_account)
    @completed_import = imports(:one) # completed status
    @pending_import = imports(:two)   # pending status
  end

  test "should get index" do
    get imports_path
    assert_response :success
    assert_select "h1", "Import History"
  end

  test "should get new" do
    get new_import_path
    assert_response :success
    assert_select "h1", "Import"
  end

  test "should show import" do
    get import_path(@completed_import)
    assert_response :success
  end

  test "create redirects without file" do
    post imports_path, params: { account_id: @account.id }
    assert_redirected_to new_import_path
    assert_equal "Please select a file to import.", flash[:alert]
  end

  test "create with file creates import record and enqueues job" do
    assert_enqueued_with(job: TransactionImportJob) do
      assert_difference("Import.count", 1) do
        post imports_path, params: {
          account_id: @account.id,
          file: fixture_file_upload("sample_upload.csv", "text/csv")
        }
      end
    end

    import = Import.last
    assert_redirected_to import_path(import)
    assert_equal "pending", import.status
    assert_equal @account.id, import.account_id
    assert_equal "sample_upload.csv", import.original_filename
    assert_equal "text/csv", import.file_content_type
  end

  test "confirm imports selected transactions" do
    # Update fixture to have extracted data
    @completed_import.update!(
      extracted_data: [
        { date: "2026-01-15", description: "Coffee", amount: 5.50, transaction_type: "expense", category_id: categories(:groceries).id }
      ].to_json
    )

    category = categories(:groceries)
    initial_count = Transaction.count

    post confirm_import_path(@completed_import), params: {
      transactions: {
        "0" => {
          selected: "1",
          date: "2026-01-15",
          description: "Coffee",
          amount: "5.50",
          transaction_type: "expense",
          category_id: category.id,
          duplicate_hash: "test_hash_1"
        }
      }
    }

    assert_redirected_to transactions_path
    assert_equal initial_count + 1, Transaction.count
    assert_match(/Successfully imported 1 transaction/, flash[:notice])

    # Check the transaction is linked to the import
    created_txn = Transaction.last
    assert_equal @completed_import.id, created_txn.import_id
  end

  test "confirm handles no transactions param" do
    initial_count = Transaction.count

    post confirm_import_path(@completed_import)

    assert_redirected_to transactions_path
    assert_equal initial_count, Transaction.count
  end

  test "confirm skips unselected transactions" do
    category = categories(:groceries)
    initial_count = Transaction.count

    post confirm_import_path(@completed_import), params: {
      transactions: {
        "0" => {
          selected: "0",
          date: "2026-01-15",
          description: "Coffee",
          amount: "5.50",
          transaction_type: "expense",
          category_id: category.id,
          duplicate_hash: "test_hash_1"
        }
      }
    }

    assert_redirected_to transactions_path
    assert_equal initial_count, Transaction.count
    assert_match(/Successfully imported 0 transactions/, flash[:notice])
  end

  test "confirm redirects if import not completed" do
    post confirm_import_path(@pending_import)

    assert_redirected_to import_path(@pending_import)
    assert_equal "Import is not ready for confirmation.", flash[:alert]
  end

  test "show pending import includes auto-refresh polling" do
    get import_path(@pending_import)
    assert_response :success
    # The page should include Stimulus polling controller
    assert_includes @response.body, 'data-controller="poll"'
  end
end

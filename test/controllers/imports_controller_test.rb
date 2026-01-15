require "test_helper"

class ImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:checking_account)
  end

  test "should get new" do
    get new_import_path
    assert_response :success
    assert_select "h1", "Import Transactions"
  end

  test "preview redirects without file" do
    post preview_imports_path, params: { account_id: @account.id }
    assert_redirected_to new_import_path
    assert_equal "Please select a file to import.", flash[:alert]
  end

  test "create imports selected transactions" do
    category = categories(:groceries)
    initial_count = Transaction.count

    post imports_path, params: {
      account_id: @account.id,
      transactions: {
        "0" => {
          selected: "1",
          date: "2026-01-15",
          description: "Coffee",
          amount: "5.50",
          transaction_type: "expense",
          category_id: category.id,
          duplicate_hash: "test_hash_1"
        },
        "1" => {
          selected: "0",  # Not selected, should be skipped
          date: "2026-01-16",
          description: "Lunch",
          amount: "12.00",
          transaction_type: "expense",
          category_id: category.id,
          duplicate_hash: "test_hash_2"
        }
      }
    }

    assert_redirected_to transactions_path
    assert_equal initial_count + 1, Transaction.count
    assert_match(/Successfully imported 1 transaction/, flash[:notice])
  end

  test "create handles no transactions param" do
    initial_count = Transaction.count

    post imports_path, params: {
      account_id: @account.id
    }

    assert_redirected_to transactions_path
    assert_equal initial_count, Transaction.count
  end

  test "create skips all unselected transactions" do
    category = categories(:groceries)
    initial_count = Transaction.count

    post imports_path, params: {
      account_id: @account.id,
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
end

require "test_helper"

class AccountTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:checking_account)
  end

  test "active scope returns non-archived accounts" do
    assert_includes Account.active, @account
    @account.update!(archived: true)
    assert_not_includes Account.active, @account
  end

  test "archived scope returns archived accounts" do
    assert_not_includes Account.archived, @account
    @account.update!(archived: true)
    assert_includes Account.archived, @account
  end

  test "archive! sets archived to true" do
    assert_not @account.archived?
    @account.archive!
    assert @account.archived?
  end

  test "unarchive! sets archived to false" do
    @account.update!(archived: true)
    assert @account.archived?
    @account.unarchive!
    assert_not @account.archived?
  end

  test "archive! raises error for account with pending imports" do
    # Create a pending import for the account
    Import.create!(
      account: @account,
      status: "pending",
      original_filename: "test.csv",
      file_content_type: "text/csv",
      file_data: "test data"
    )

    assert @account.has_pending_imports?
    assert_raises(ActiveRecord::RecordInvalid) do
      @account.archive!
    end
    assert_not @account.reload.archived?
  end

  test "archive! raises error for account with processing imports" do
    # Create a processing import for the account
    Import.create!(
      account: @account,
      status: "processing",
      original_filename: "test.csv",
      file_content_type: "text/csv",
      file_data: "test data"
    )

    assert @account.has_pending_imports?
    assert_raises(ActiveRecord::RecordInvalid) do
      @account.archive!
    end
    assert_not @account.reload.archived?
  end

  test "archive! succeeds for account with completed imports" do
    # Create a completed import for the account
    Import.create!(
      account: @account,
      status: "completed",
      original_filename: "test.csv",
      file_content_type: "text/csv",
      file_data: "test data"
    )

    assert_not @account.has_pending_imports?
    @account.archive!
    assert @account.archived?
  end

  test "archive! succeeds for account with done imports" do
    # Create a done import for the account
    Import.create!(
      account: @account,
      status: "done",
      original_filename: "test.csv",
      file_content_type: "text/csv",
      file_data: "test data"
    )

    assert_not @account.has_pending_imports?
    @account.archive!
    assert @account.archived?
  end

  test "new accounts default to not archived" do
    account = Account.new(
      name: "Test Account",
      account_type: account_types(:checking),
      balance: 0,
      currency: "USD"
    )
    assert_not account.archived?
  end

  test "ignore_patterns_list returns defaults when blank" do
    @account.import_ignore_patterns = nil

    patterns = @account.ignore_patterns_list
    assert_includes patterns, "Total"
    assert_includes patterns, "Balance"
    assert_includes patterns, "Subtotal"
  end

  test "ignore_patterns_list returns custom patterns when set" do
    @account.import_ignore_patterns = "Custom Pattern\nAnother Pattern"

    assert_equal [ "Custom Pattern", "Another Pattern" ], @account.ignore_patterns_list
  end

  test "ignore_patterns_list strips whitespace and rejects blank lines" do
    @account.import_ignore_patterns = "  Pattern One  \n\n  Pattern Two  \n  "

    assert_equal [ "Pattern One", "Pattern Two" ], @account.ignore_patterns_list
  end

  test "should_ignore_for_import? returns true for matching description" do
    @account.import_ignore_patterns = "Total\nBalance"

    assert @account.should_ignore_for_import?("Total Amount Due")
    assert @account.should_ignore_for_import?("Account Balance")
  end

  test "should_ignore_for_import? returns false for non-matching description" do
    @account.import_ignore_patterns = "Total\nBalance"

    assert_not @account.should_ignore_for_import?("Amazon Purchase")
    assert_not @account.should_ignore_for_import?("Grocery Store")
  end

  test "should_ignore_for_import? is case-sensitive" do
    @account.import_ignore_patterns = "Total"

    assert @account.should_ignore_for_import?("Total Amount")
    assert_not @account.should_ignore_for_import?("total amount")
  end
end

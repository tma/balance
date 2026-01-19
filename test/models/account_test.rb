require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "ignore_patterns_list returns defaults when blank" do
    account = accounts(:checking_account)
    account.import_ignore_patterns = nil

    patterns = account.ignore_patterns_list
    assert_includes patterns, "Total"
    assert_includes patterns, "Balance"
    assert_includes patterns, "Subtotal"
  end

  test "ignore_patterns_list returns custom patterns when set" do
    account = accounts(:checking_account)
    account.import_ignore_patterns = "Custom Pattern\nAnother Pattern"

    assert_equal [ "Custom Pattern", "Another Pattern" ], account.ignore_patterns_list
  end

  test "ignore_patterns_list strips whitespace and rejects blank lines" do
    account = accounts(:checking_account)
    account.import_ignore_patterns = "  Pattern One  \n\n  Pattern Two  \n  "

    assert_equal [ "Pattern One", "Pattern Two" ], account.ignore_patterns_list
  end

  test "should_ignore_for_import? returns true for matching description" do
    account = accounts(:checking_account)
    account.import_ignore_patterns = "Total\nBalance"

    assert account.should_ignore_for_import?("Total Amount Due")
    assert account.should_ignore_for_import?("Account Balance")
  end

  test "should_ignore_for_import? returns false for non-matching description" do
    account = accounts(:checking_account)
    account.import_ignore_patterns = "Total\nBalance"

    assert_not account.should_ignore_for_import?("Amazon Purchase")
    assert_not account.should_ignore_for_import?("Grocery Store")
  end

  test "should_ignore_for_import? is case-sensitive" do
    account = accounts(:checking_account)
    account.import_ignore_patterns = "Total"

    assert account.should_ignore_for_import?("Total Amount")
    assert_not account.should_ignore_for_import?("total amount")
  end
end

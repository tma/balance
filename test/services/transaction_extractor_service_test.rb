require "test_helper"

class TransactionExtractorServiceTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:checking_account)
    @text = "Statement\n2026-01-15 COFFEE SHOP 5.50\n2026-01-16 SALARY DEPOSIT 2000.00"
  end

  test "initializes with text and account" do
    extractor = TransactionExtractorService.new(@text, @account)

    assert_equal @text, extractor.text
    assert_equal @account, extractor.account
  end

  test "error classes are defined" do
    assert_kind_of Class, TransactionExtractorService::Error
    assert_kind_of Class, TransactionExtractorService::ExtractionError
    assert TransactionExtractorService::ExtractionError < TransactionExtractorService::Error
  end
end

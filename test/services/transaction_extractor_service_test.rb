require "test_helper"

class TransactionExtractorServiceTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:checking_account)
    @text = "Statement\n2026-01-15 COFFEE SHOP 5.50\n2026-01-16 SALARY DEPOSIT 2000.00"
  end

  test "initializes with text and account (backward compatibility)" do
    extractor = TransactionExtractorService.new(@text, @account)

    assert_equal @text, extractor.text
    assert_equal [ @text ], extractor.chunks
    assert_equal @account, extractor.account
  end

  test "initializes with array of chunks" do
    chunks = [ "Page 1 content", "Page 2 content" ]
    extractor = TransactionExtractorService.new(chunks, @account)

    assert_equal chunks, extractor.chunks
    assert_equal @account, extractor.account
    assert_equal "Page 1 content", extractor.text # First chunk for backward compat
  end

  test "error classes are defined" do
    assert_kind_of Class, TransactionExtractorService::Error
    assert_kind_of Class, TransactionExtractorService::ExtractionError
    assert TransactionExtractorService::ExtractionError < TransactionExtractorService::Error
  end
end

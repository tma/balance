require "test_helper"

class PdfParserServiceTest < ActiveSupport::TestCase
  # ========================================
  # Tests for file size validation
  # ========================================

  test "raises error when file size exceeds maximum" do
    # Create a mock file that reports a large size
    large_file = Struct.new(:size).new(10.megabytes)

    error = assert_raises(PdfParserService::Error) do
      PdfParserService.extract_pages(large_file)
    end
    assert_match(/File too large/, error.message)
    assert_match(/5MB/, error.message)
  end

  test "accepts file within size limit" do
    skip "OCR dependencies not available" unless OcrService.available?

    # Create a small valid PDF
    pdf_path = create_test_pdf("Small file content")

    begin
      # Should not raise file size error
      pages = PdfParserService.extract_pages(pdf_path)
      assert_kind_of Array, pages
    ensure
      File.delete(pdf_path) if File.exist?(pdf_path)
    end
  end

  # ========================================
  # Tests for OCR availability check
  # ========================================

  test "raises error when OCR service is not available" do
    OcrService.define_singleton_method(:available?) { false }

    begin
      small_file = Struct.new(:size).new(1.kilobyte)

      error = assert_raises(PdfParserService::Error) do
        PdfParserService.extract_pages(small_file)
      end
      assert_match(/OCR is not available/, error.message)
    ensure
      OcrService.define_singleton_method(:available?) do
        tesseract_available? && pdftoppm_available?
      end
    end
  end

  # ========================================
  # Tests for normalize_io private method
  # ========================================

  test "normalize_io handles file with tempfile method" do
    mock_tempfile = StringIO.new("content")
    mock_upload = Struct.new(:tempfile).new(mock_tempfile)

    result = PdfParserService.send(:normalize_io, mock_upload)
    assert_equal mock_tempfile, result
  end

  test "normalize_io handles file with read method" do
    io = StringIO.new("PDF content")

    result = PdfParserService.send(:normalize_io, io)
    assert_equal io, result
  end

  test "normalize_io passes through string paths" do
    path = "/some/path/to/file.pdf"

    result = PdfParserService.send(:normalize_io, path)
    assert_equal path, result
  end

  # ========================================
  # Tests for text cleanup methods
  # ========================================

  test "repeated_line_matches identifies repeated lines across pages" do
    pages = [
      "Header Line\nTransaction 1\nFooter Line",
      "Header Line\nTransaction 2\nFooter Line"
    ]

    result = PdfParserService.send(:repeated_line_matches, pages)

    # Header and Footer should be identified as repeated
    assert_includes result, "Header Line"
    assert_includes result, "Footer Line"
    refute_includes result, "Transaction 1"
    refute_includes result, "Transaction 2"
  end

  test "repeated_line_matches ignores short lines" do
    pages = [
      "OK\nTransaction 1",
      "OK\nTransaction 2"
    ]

    result = PdfParserService.send(:repeated_line_matches, pages)

    # "OK" is too short (< 8 chars) to be considered repeated
    refute_includes result, "OK"
  end

  test "normalize_text handles various encodings" do
    # Non-breaking space and other special characters
    text = "Amount\u00A01,000.00\r\nDescription"

    result = PdfParserService.send(:normalize_text, text)

    # Non-breaking space should be converted to regular space
    assert_match(/Amount 1,000.00/, result)
    # \r\n should be normalized to \n
    assert_match(/\n/, result)
    refute_match(/\r/, result)
  end

  # ========================================
  # Tests for continuation line merging
  # ========================================

  test "merge_transaction_continuations joins continuation lines" do
    lines = [
      "01.01.2026 Payment to merchant",
      "Additional description text",
      "100.00"
    ]

    result = PdfParserService.send(:merge_transaction_continuations, lines)

    # Middle line should be merged with first line
    assert_match(/Payment to merchant Additional description text/, result)
  end

  test "continuation_line returns false for lines starting with date" do
    line = "01.01.2026 New transaction"

    result = PdfParserService.send(:continuation_line?, line)

    assert_equal false, result
  end

  test "continuation_line returns false for lines with amounts" do
    line = "Total: 1,234.56"

    result = PdfParserService.send(:continuation_line?, line)

    assert_equal false, result
  end

  test "continuation_line returns true for description text without dates or amounts" do
    line = "Additional merchant information"

    result = PdfParserService.send(:continuation_line?, line)

    assert_equal true, result
  end

  test "continuation_line returns false for blank lines" do
    result = PdfParserService.send(:continuation_line?, "")
    assert_equal false, result

    result = PdfParserService.send(:continuation_line?, "   ")
    assert_equal false, result
  end

  # ========================================
  # Tests for extract_text method
  # ========================================

  test "extract_text returns joined pages" do
    skip "OCR dependencies not available" unless OcrService.available?

    pdf_path = create_test_pdf("Test content for extraction")

    begin
      text = PdfParserService.extract_text(pdf_path)
      assert_kind_of String, text
    ensure
      File.delete(pdf_path) if File.exist?(pdf_path)
    end
  end

  # ========================================
  # Tests for extract_pages_with_ocr alias
  # ========================================

  test "extract_pages_with_ocr is an alias for extract_pages" do
    skip "OCR dependencies not available" unless OcrService.available?

    pdf_path = create_test_pdf("Alias test")

    begin
      pages1 = PdfParserService.extract_pages(pdf_path)
      pages2 = PdfParserService.extract_pages_with_ocr(pdf_path)

      assert_equal pages1, pages2
    ensure
      File.delete(pdf_path) if File.exist?(pdf_path)
    end
  end

  # ========================================
  # Tests for error handling
  # ========================================

  test "wraps OcrService errors in PdfParserService::Error" do
    skip "OCR dependencies not available" unless OcrService.available?

    # Create a corrupted file
    Tempfile.create(["corrupted", ".pdf"]) do |file|
      file.write("Not a valid PDF")
      file.close

      error = assert_raises(PdfParserService::Error) do
        PdfParserService.extract_pages(file.path)
      end
      assert_match(/PDF extraction failed|No text could be extracted/, error.message)
    end
  end

  test "raises error when no text is extracted" do
    skip "OCR dependencies not available" unless OcrService.available?

    # Mock OcrService to return empty pages
    original_method = OcrService.method(:extract_pages)
    OcrService.define_singleton_method(:extract_pages) { |*_args| [] }

    begin
      small_file = StringIO.new("dummy content")

      error = assert_raises(PdfParserService::Error) do
        PdfParserService.extract_pages(small_file)
      end
      assert_match(/No text could be extracted/, error.message)
    ensure
      OcrService.define_singleton_method(:extract_pages, original_method)
    end
  end

  # ========================================
  # Integration tests
  # ========================================

  test "extract_pages processes a valid PDF successfully" do
    skip "OCR dependencies not available" unless OcrService.available?

    pdf_path = create_test_pdf("01.01.2026 Coffee Shop 5.50\n02.01.2026 Grocery Store 45.00")

    begin
      pages = PdfParserService.extract_pages(pdf_path)

      assert_kind_of Array, pages
      refute_empty pages
    ensure
      File.delete(pdf_path) if File.exist?(pdf_path)
    end
  end

  private

  def create_test_pdf(content)
    require "prawn"

    pdf_path = Tempfile.new(["test", ".pdf"]).path

    Prawn::Document.generate(pdf_path) do
      text content
    end

    pdf_path
  rescue LoadError
    skip "Prawn gem not available for creating test PDFs"
  end
end

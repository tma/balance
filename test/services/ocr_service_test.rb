require "test_helper"

class OcrServiceTest < ActiveSupport::TestCase
  # ========================================
  # Tests for available? method
  # ========================================

  test "available? returns true when both tesseract and pdftoppm are installed" do
    # Skip if dependencies are not available in the test environment
    skip "Tesseract not available" unless system("which tesseract > /dev/null 2>&1")
    skip "pdftoppm not available" unless system("which pdftoppm > /dev/null 2>&1")

    assert OcrService.available?
  end

  # ========================================
  # Tests for validate_dependencies!
  # ========================================

  test "raises error when tesseract is not available" do
    # Store the original method implementation
    original_impl = OcrService.method(:tesseract_available?)

    OcrService.define_singleton_method(:tesseract_available?) { false }

    begin
      error = assert_raises(OcrService::Error) do
        OcrService.send(:validate_dependencies!)
      end
      assert_match(/Tesseract OCR is not installed/, error.message)
    ensure
      # Restore original method using the captured implementation
      OcrService.define_singleton_method(:tesseract_available?, original_impl)
    end
  end

  test "raises error when pdftoppm is not available" do
    # Only test if tesseract is available, otherwise the first check fails
    skip "Tesseract not available" unless system("which tesseract > /dev/null 2>&1")

    # Store the original method implementation
    original_impl = OcrService.method(:pdftoppm_available?)

    OcrService.define_singleton_method(:pdftoppm_available?) { false }

    begin
      error = assert_raises(OcrService::Error) do
        OcrService.send(:validate_dependencies!)
      end
      assert_match(/pdftoppm is not installed/, error.message)
    ensure
      # Restore original method using the captured implementation
      OcrService.define_singleton_method(:pdftoppm_available?, original_impl)
    end
  end

  # ========================================
  # Tests for normalize_text private method
  # ========================================

  test "normalize_text removes control characters" do
    text = "Hello\x00World\x08Test"
    result = OcrService.send(:normalize_text, text)
    assert_equal "Hello World Test", result
  end

  test "normalize_text collapses multiple spaces" do
    text = "Hello    World   Test"
    result = OcrService.send(:normalize_text, text)
    assert_equal "Hello World Test", result
  end

  test "normalize_text collapses multiple newlines" do
    text = "Line1\n\n\n\nLine2"
    result = OcrService.send(:normalize_text, text)
    assert_equal "Line1\n\nLine2", result
  end

  test "normalize_text handles nil input" do
    result = OcrService.send(:normalize_text, nil)
    assert_equal "", result
  end

  test "normalize_text strips leading and trailing whitespace" do
    text = "   Hello World   "
    result = OcrService.send(:normalize_text, text)
    assert_equal "Hello World", result
  end

  # ========================================
  # Tests for file_to_path private method
  # ========================================

  test "file_to_path handles string path that exists" do
    Tempfile.create(["test", ".pdf"]) do |file|
      file.write("test content")
      file.close
      result = OcrService.send(:file_to_path, file.path)
      assert_equal file.path, result
    end
  end

  test "file_to_path handles object with tempfile method" do
    mock_upload = Struct.new(:tempfile).new(
      Struct.new(:path).new("/tmp/uploaded.pdf")
    )

    result = OcrService.send(:file_to_path, mock_upload)
    assert_equal "/tmp/uploaded.pdf", result
  end

  test "file_to_path handles object with path method" do
    mock_file = Struct.new(:path).new("/tmp/some_file.pdf")

    result = OcrService.send(:file_to_path, mock_file)
    assert_equal "/tmp/some_file.pdf", result
  end

  test "file_to_path creates temp file for IO objects" do
    io = StringIO.new("PDF content here")

    begin
      result = OcrService.send(:file_to_path, io)
      assert File.exist?(result)
      assert_equal "PDF content here", File.read(result)
    ensure
      # Clean up temp file reference
      OcrService.instance_variable_set(:@temp_pdf, nil)
    end
  end

  test "file_to_path raises error for unsupported file type" do
    error = assert_raises(OcrService::Error) do
      OcrService.send(:file_to_path, 12345)
    end
    assert_match(/Unable to process file/, error.message)
  end

  # ========================================
  # Integration tests (require OCR dependencies)
  # ========================================

  test "extract_pages extracts text from a simple PDF" do
    skip "OCR dependencies not available" unless OcrService.available?

    # Create a simple test PDF with text
    pdf_path = create_test_pdf_with_text("Hello World\nThis is a test.")

    begin
      pages = OcrService.extract_pages(pdf_path)
      assert_kind_of Array, pages
      # OCR should extract something, though exact text may vary
      refute_empty pages
    ensure
      File.delete(pdf_path) if File.exist?(pdf_path)
    end
  end

  test "extract_text returns single string" do
    skip "OCR dependencies not available" unless OcrService.available?

    pdf_path = create_test_pdf_with_text("Test content")

    begin
      text = OcrService.extract_text(pdf_path)
      assert_kind_of String, text
    ensure
      File.delete(pdf_path) if File.exist?(pdf_path)
    end
  end

  test "extract_pages handles multi-page PDF" do
    skip "OCR dependencies not available" unless OcrService.available?

    pdf_path = create_multi_page_test_pdf

    begin
      pages = OcrService.extract_pages(pdf_path)
      assert_kind_of Array, pages
      # Should have content from pages
      refute_empty pages
    ensure
      File.delete(pdf_path) if File.exist?(pdf_path)
    end
  end

  test "extract_pages raises error for corrupted PDF" do
    skip "OCR dependencies not available" unless OcrService.available?

    # Create a file that's not a valid PDF
    Tempfile.create(["corrupted", ".pdf"]) do |file|
      file.write("This is not a valid PDF file content")
      file.close

      assert_raises(OcrService::Error) do
        OcrService.extract_pages(file.path)
      end
    end
  end

  test "extract_pages cleans up temporary files" do
    skip "OCR dependencies not available" unless OcrService.available?

    pdf_path = create_test_pdf_with_text("Cleanup test")

    begin
      # Count temp dirs before
      temp_dirs_before = Dir.glob("/tmp/pdf_ocr*").count

      OcrService.extract_pages(pdf_path)

      # Temp dirs should be cleaned up
      temp_dirs_after = Dir.glob("/tmp/pdf_ocr*").count
      assert temp_dirs_after <= temp_dirs_before, "Temporary directories were not cleaned up"
    ensure
      File.delete(pdf_path) if File.exist?(pdf_path)
    end
  end

  private

  def create_test_pdf_with_text(text)
    require "prawn"

    pdf_path = Tempfile.new(["test", ".pdf"]).path

    Prawn::Document.generate(pdf_path) do
      text text
    end

    pdf_path
  rescue LoadError
    skip "Prawn gem not available for creating test PDFs"
  end

  def create_multi_page_test_pdf
    require "prawn"

    pdf_path = Tempfile.new(["multipage", ".pdf"]).path

    Prawn::Document.generate(pdf_path) do
      text "Page 1 content"
      start_new_page
      text "Page 2 content"
    end

    pdf_path
  rescue LoadError
    skip "Prawn gem not available for creating test PDFs"
  end
end

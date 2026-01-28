require "test_helper"

class OcrServiceTest < ActiveSupport::TestCase
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
    Tempfile.create([ "test", ".pdf" ]) do |file|
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
end

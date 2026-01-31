require "test_helper"
require "webmock/minitest"

class PdfTextExtractorServiceTest < ActiveSupport::TestCase
  setup do
    # Stub Ollama availability check
    stub_request(:get, "#{Rails.application.config.ollama.host}/api/tags")
      .to_return(status: 200, body: { models: [ { name: "llama3.2" } ] }.to_json)
  end

  test "extracts CSV from response without markdown" do
    csv_content = "Date,Description,Amount\n2024-01-15,Coffee Shop,12.50"

    result = PdfTextExtractorService.send(:extract_csv_from_response, csv_content)

    assert_equal csv_content, result
  end

  test "extracts CSV from response with markdown code block" do
    response = "```csv\nDate,Description,Amount\n2024-01-15,Coffee Shop,12.50\n```"

    result = PdfTextExtractorService.send(:extract_csv_from_response, response)

    assert_equal "Date,Description,Amount\n2024-01-15,Coffee Shop,12.50", result
  end

  test "extracts CSV from response with plain markdown code block" do
    response = "```\nDate,Description,Amount\n2024-01-15,Coffee Shop,12.50\n```"

    result = PdfTextExtractorService.send(:extract_csv_from_response, response)

    assert_equal "Date,Description,Amount\n2024-01-15,Coffee Shop,12.50", result
  end

  test "returns empty string for blank response" do
    assert_equal "", PdfTextExtractorService.send(:extract_csv_from_response, "")
    assert_equal "", PdfTextExtractorService.send(:extract_csv_from_response, nil)
  end

  test "returns empty string for single line response" do
    result = PdfTextExtractorService.send(:extract_csv_from_response, "No transactions found")

    assert_equal "", result
  end

  test "raises error for file too large" do
    large_file = StringIO.new("x" * (6.megabytes))

    error = assert_raises(PdfTextExtractorService::Error) do
      PdfTextExtractorService.extract_csv(large_file)
    end

    assert_match(/too large/i, error.message)
  end

  test "build_prompt includes document text" do
    text = "Sample bank statement text"

    prompt = PdfTextExtractorService.send(:build_prompt, text)

    assert_includes prompt, text
    assert_includes prompt, "transaction table"
    assert_includes prompt, "CSV"
  end

  test "extracts text from PDF using pdftotext" do
    # This test requires pdftotext to be installed
    skip "pdftotext not available" unless system("which pdftotext > /dev/null 2>&1")

    # We can't easily create a valid PDF in tests, so we test the error handling
    Tempfile.create([ "test", ".pdf" ]) do |temp_file|
      temp_file.write("not a valid pdf")
      temp_file.rewind

      # pdftotext will fail on invalid PDF
      error = assert_raises(PdfTextExtractorService::Error) do
        PdfTextExtractorService.send(:extract_text, temp_file.path)
      end

      assert_match(/Failed to extract/i, error.message)
    end
  end

  test "convert_to_csv calls OllamaService and extracts CSV" do
    sample_text = "Date       Description    Amount\n2024-01-15 Coffee Shop    12.50"
    csv_response = "Date,Description,Amount\n2024-01-15,Coffee Shop,12.50"

    stub_request(:post, "#{Rails.application.config.ollama.host}/api/generate")
      .to_return(status: 200, body: { response: csv_response }.to_json, headers: { "Content-Type" => "application/json" })

    result = PdfTextExtractorService.send(:convert_to_csv, sample_text)

    assert_equal csv_response, result
  end

  test "convert_to_csv raises error when LLM returns invalid CSV" do
    sample_text = "Some PDF text"

    stub_request(:post, "#{Rails.application.config.ollama.host}/api/generate")
      .to_return(status: 200, body: { response: "I couldn't find any transactions" }.to_json)

    error = assert_raises(PdfTextExtractorService::Error) do
      PdfTextExtractorService.send(:convert_to_csv, sample_text)
    end

    assert_match(/Could not extract transactions/i, error.message)
  end

  test "convert_to_csv wraps OllamaService errors" do
    sample_text = "Some PDF text"

    stub_request(:post, "#{Rails.application.config.ollama.host}/api/generate")
      .to_return(status: 500, body: "Internal Server Error")

    error = assert_raises(PdfTextExtractorService::Error) do
      PdfTextExtractorService.send(:convert_to_csv, sample_text)
    end

    assert_match(/AI extraction failed/i, error.message)
  end

  test "truncates very long text before sending to LLM" do
    long_text = "x" * 60_000

    # Capture the request to verify prompt length
    request_body = nil
    stub_request(:post, "#{Rails.application.config.ollama.host}/api/generate")
      .with { |request| request_body = JSON.parse(request.body); true }
      .to_return(status: 200, body: { response: "Date,Desc,Amt\n1,2,3" }.to_json, headers: { "Content-Type" => "application/json" })

    PdfTextExtractorService.send(:convert_to_csv, long_text)

    # The prompt should contain truncated text (MAX_TEXT_LENGTH = 50_000)
    assert request_body["prompt"].length < 60_000
  end

  test "file_to_path handles string path" do
    path = "/tmp/test.pdf"
    File.write(path, "test")

    result = PdfTextExtractorService.send(:file_to_path, path)

    assert_equal path, result
  ensure
    File.delete(path) if File.exist?(path)
  end

  test "file_to_path handles file with tempfile" do
    temp = Tempfile.new([ "test", ".pdf" ])
    temp.write("test")
    temp.close

    mock_file = Struct.new(:tempfile).new(temp)

    result = PdfTextExtractorService.send(:file_to_path, mock_file)

    assert_equal temp.path, result
  ensure
    temp.unlink
  end

  test "file_to_path handles IO object" do
    io = StringIO.new("test pdf content")

    result = PdfTextExtractorService.send(:file_to_path, io)

    assert File.exist?(result)
    assert_equal "test pdf content", File.read(result)
  end

  test "file_to_path raises error for unknown type" do
    error = assert_raises(PdfTextExtractorService::Error) do
      PdfTextExtractorService.send(:file_to_path, 12345)
    end

    assert_match(/Unable to process file/i, error.message)
  end
end

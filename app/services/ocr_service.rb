require "rtesseract"
require "tempfile"
require "open3"

class OcrService
  class Error < StandardError; end

  # Default languages for OCR (English, German, French)
  DEFAULT_LANGUAGES = %w[eng deu fra].freeze

  # DPI for PDF to image conversion (higher = better quality but slower)
  DEFAULT_DPI = 300

  class << self
    # Extract text from a PDF file using OCR, returning an array of pages
    # @param file [ActionDispatch::Http::UploadedFile, File, IO, String] The PDF file or path
    # @param languages [Array<String>] Tesseract language codes to use
    # @return [Array<String>] Array of text content per page
    def extract_pages(file, languages: DEFAULT_LANGUAGES)
      @temp_image_dir = nil
      @temp_pdf = nil
      validate_dependencies!

      pdf_path = file_to_path(file)
      image_paths = pdf_to_images(pdf_path)

      pages = image_paths.map do |image_path|
        ocr_image(image_path, languages: languages)
      end

      pages.reject(&:empty?)
    ensure
      # Clean up temporary directories
      FileUtils.rm_rf(@temp_image_dir) if @temp_image_dir
      FileUtils.rm_f(@temp_pdf.path) if @temp_pdf
    end

    # Extract all text as a single string
    # @param file [ActionDispatch::Http::UploadedFile, File, IO, String] The PDF file or path
    # @param languages [Array<String>] Tesseract language codes to use
    # @return [String] The extracted text
    def extract_text(file, languages: DEFAULT_LANGUAGES)
      extract_pages(file, languages: languages).join("\n\n")
    end

    # Check if OCR dependencies are available
    # @return [Boolean]
    def available?
      tesseract_available? && pdftoppm_available?
    end

    private

    def validate_dependencies!
      unless tesseract_available?
        raise Error, "Tesseract OCR is not installed. Install with: apt-get install tesseract-ocr"
      end

      unless pdftoppm_available?
        raise Error, "pdftoppm is not installed. Install with: apt-get install poppler-utils"
      end
    end

    def tesseract_available?
      system("which tesseract > /dev/null 2>&1")
    end

    def pdftoppm_available?
      system("which pdftoppm > /dev/null 2>&1")
    end

    # Convert file/IO to a file path, creating a temp file if needed
    def file_to_path(file)
      if file.is_a?(String) && File.exist?(file)
        file
      elsif file.respond_to?(:tempfile)
        file.tempfile.path
      elsif file.respond_to?(:path)
        file.path
      elsif file.respond_to?(:read)
        # Create a temp file for IO objects
        temp = Tempfile.new([ "pdf_ocr", ".pdf" ])
        temp.binmode
        file.rewind if file.respond_to?(:rewind)
        temp.write(file.read)
        temp.close
        @temp_pdf = temp  # Keep reference to prevent GC
        temp.path
      else
        raise Error, "Unable to process file: #{file.class}"
      end
    end

    # Convert PDF to images using pdftoppm
    # @param pdf_path [String] Path to the PDF file
    # @return [Array<String>] Paths to generated image files
    def pdf_to_images(pdf_path)
      # Create a persistent temp directory (caller is responsible for cleanup)
      tmpdir = Dir.mktmpdir("pdf_ocr")
      output_prefix = File.join(tmpdir, "page")

      # Use pdftoppm to convert PDF to PNG images
      stdout, stderr, status = Open3.capture3(
        "pdftoppm",
        "-png",
        "-r", DEFAULT_DPI.to_s,
        pdf_path,
        output_prefix
      )

      unless status.success?
        FileUtils.rm_rf(tmpdir)
        raise Error, "Failed to convert PDF to images: #{stderr}"
      end

      # Find all generated images, sorted by page number
      image_files = Dir.glob("#{output_prefix}-*.png").sort_by do |f|
        # Extract page number from filename (e.g., "page-01.png" -> 1)
        f[/-(\d+)\.png$/, 1].to_i
      end

      if image_files.empty?
        FileUtils.rm_rf(tmpdir)
        raise Error, "No images were generated from the PDF"
      end

      # Store tmpdir for cleanup later
      @temp_image_dir = tmpdir

      image_files
    end

    # Perform OCR on a single image
    # @param image_path [String] Path to the image file
    # @param languages [Array<String>] Tesseract language codes
    # @return [String] Extracted text
    def ocr_image(image_path, languages:)
      # Filter to only available languages
      available_langs = available_languages
      langs_to_use = languages.select { |l| available_langs.include?(l) }
      langs_to_use = [ "eng" ] if langs_to_use.empty?  # Fallback to English

      rtesseract = RTesseract.new(image_path, lang: langs_to_use.join("+"))
      text = rtesseract.to_s

      normalize_text(text)
    rescue => e
      raise Error, "OCR failed: #{e.message}"
    end

    # Get list of installed Tesseract languages
    def available_languages
      @available_languages ||= begin
        stdout, _, status = Open3.capture3("tesseract --list-langs")
        if status.success?
          stdout.lines.drop(1).map(&:strip)
        else
          []
        end
      end
    end

    # Clean up extracted text
    def normalize_text(text)
      return "" if text.nil?

      text
        .gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, " ")  # Remove control chars
        .gsub(/[ \t]+/, " ")          # Collapse multiple spaces/tabs
        .gsub(/ ?\n ?/, "\n")         # Remove spaces around newlines
        .gsub(/\n{3,}/, "\n\n")       # Collapse 3+ newlines to 2
        .strip
    end
  end
end

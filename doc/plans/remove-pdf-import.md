# Remove PDF Import & Dead Code

## Problem
The PDF import feature adds complexity and extra LLM calls but is unused — only CSV import is used in practice. The `TransactionExtractorService` is also dead code (legacy, never invoked). This plan removes both to simplify the codebase.

## Files to Delete (6 files)

| File | Reason |
|------|--------|
| `app/services/pdf_text_extractor_service.rb` | PDF-specific service (146 lines) |
| `app/services/transaction_extractor_service.rb` | Dead code, legacy extractor (341 lines) |
| `test/services/pdf_text_extractor_service_test.rb` | Tests for deleted service (179 lines) |
| `test/services/transaction_extractor_service_test.rb` | Tests for deleted service (452 lines) |
| `test/fixtures/files/sample_statement.pdf` | PDF test fixture (unused) |
| `tmp/benchmark_results.json` | Contains PDF-specific benchmark data (optional, tmp file) |

## Files to Modify (9 files)

### 1. `app/jobs/transaction_import_job.rb`
- Remove `process_pdf()` method (lines 118-140)
- Remove `process_pdf_csv_content()` method (lines 142-160)
- Remove PDF branch in `perform`: simplify `if import.csv?` / `else` to just call `process_csv(import)` directly (lines 15-19)
- Remove `PdfTextExtractorService::Error` from rescue (line 27)
- Remove `TransactionExtractorService::ExtractionError` from rescue (line 33)

### 2. `app/models/import.rb`
- Remove `pdf?` method (lines 43-45)

### 3. `app/controllers/imports_controller.rb`
- Simplify `determine_content_type()`: remove PDF detection branch (lines 234-235), keep CSV and fallback to `text/plain`
- Remove the `if @import.file_content_type == "text/csv"` guard on line 196 in `reprocess` — now always CSV, so always clear cached mapping

### 4. `app/views/imports/new.html.erb`
- Line 33: Change "PDF or CSV file (max 5MB)" → "CSV file (max 5MB)"
- Line 36: Change `accept: ".pdf,.csv,application/pdf,text/csv"` → `accept: ".csv,text/csv"`
- Line 54: Change "Upload a statement (PDF or CSV format)" → "Upload a bank statement (CSV format)"

### 5. `app/views/imports/_import_row.html.erb`
- Remove the `if import.pdf?` branch (lines 5-8), keep only the emerald CSV icon (lines 10-12), remove the `else`/`end`

### 6. `test/fixtures/imports.yml`
- Fixture `two` (line 14-23): Change from PDF to CSV (change filename to `statement.csv`, content type to `text/csv`, file_data to CSV content)
- Fixture `three` (line 25-34): Change from PDF to CSV (change filename to `bad_file.csv`, content type to `text/csv`)

### 7. `Dockerfile` (production)
- Remove lines 21-22 (PDF comment + `poppler-utils \`)

### 8. `.devcontainer/Dockerfile`
- Remove lines 18-19 (PDF comment + `poppler-utils \`)

### 9. Documentation updates
- `SPEC.md`: Update lines 42, 45, 316 — remove PDF references and `PdfTextExtractorService`/`TransactionExtractorService` from service list
- `README.md`: Update lines 20, 112 — remove PDF references

## Files NOT Modified (no changes needed)
- `db/schema.rb` / migrations — `file_content_type` column stays (still used for CSV)
- `config/routes.rb` — no PDF-specific routes
- `doc/plans/*.md` — historical records, never modify per AGENTS.md rules
- `test/controllers/imports_controller_test.rb` — references fixtures `:two` and `:three` by status role (pending/failed), not PDF-specific; fixtures will be updated to CSV so tests continue to work as-is

## Validation
After implementation:
1. `docker exec balance-devcontainer bin/rails test` — all tests pass
2. `docker exec balance-devcontainer rubocop` — no offenses
3. Verify upload form only accepts CSV
4. Verify imports index renders correctly without PDF icon logic

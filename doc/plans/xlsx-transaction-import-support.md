# XLS(X) transaction import support

## Problem
Transaction import currently accepts CSV files only. Users need `.xls` and `.xlsx` support with the same downstream behavior as CSV imports.

## Approach
- Accept CSV/XLS/XLSX in the import UI and content-type detection.
- Normalize spreadsheet files to CSV text before existing mapping/parsing services.
- Reuse existing mapping cache and categorization pipeline unchanged.
- For multi-worksheet spreadsheets, import only the first non-empty worksheet and show this in upload fine print.

## Files to modify
- `Gemfile` / `Gemfile.lock` (spreadsheet parser dependency)
- `app/views/imports/new.html.erb`
- `app/controllers/imports_controller.rb`
- `app/jobs/transaction_import_job.rb`
- `app/services/*` (new normalization service)
- `test/controllers/imports_controller_test.rb`
- `test/services/*` (normalization tests)
- `README.md`
- `SPEC.md`

## Considerations
- Keep current 5MB limit and error handling semantics.
- Keep import processing flow and progress UX consistent.
- Ensure CSV behavior remains unchanged.

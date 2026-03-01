# Review CSV parse services follow-up fixes

## Problem
During a full review of CSV parsing services, grouped detail rows with negative values in the detail amount column are currently discarded.

## Proposed solution
1. Update `DeterministicCsvParserService#parse_detail_row` to accept negative non-zero detail amounts.
2. Keep amount normalization via `abs` and inherited transaction type behavior.
3. Add regression test coverage for grouped detail rows with negative detail amounts.

## Files to modify
- `app/services/deterministic_csv_parser_service.rb`
- `test/services/deterministic_csv_parser_service_test.rb`

## Considerations
- Preserve existing behavior for zero-value detail rows (still ignored).
- Do not alter grouped summary-tolerance behavior in this fix.
- Validate with targeted tests, full `rails test`, and `rubocop` in devcontainer.

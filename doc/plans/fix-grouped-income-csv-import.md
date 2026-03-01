# Fix grouped income CSV import

## Problem
Swiss detailed statement imports can miss income transactions when grouped rows are present.  
For grouped income sections, the parser currently assumes detail rows are always expenses and can drop the income header as a summary row.

## Proposed solution
1. In `DeterministicCsvParserService`, pass the grouped header transaction type into detail row parsing.
2. Make detail rows inherit their header type instead of always forcing `"expense"`.
3. Add a regression test for grouped income rows where header amount equals detail sum and details must be imported as income.

## Files to modify
- `app/services/deterministic_csv_parser_service.rb`
- `test/services/deterministic_csv_parser_service_test.rb`

## Considerations
- Keep existing grouped-expense behavior unchanged.
- Keep summary-row suppression unchanged.
- Validate with parser tests, full test suite, and rubocop in devcontainer.

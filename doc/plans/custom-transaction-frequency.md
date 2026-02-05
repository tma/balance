# Custom Transaction Frequency

## Problem
The transaction frequency field on accounts only allows preset values (7, 30, 90 days).
Real-world transactions don't always fall on exact intervals — e.g., quarterly
transactions can be 91-93 days apart, causing false gap alerts.

## Solution
Replace the select-only UI with a numeric input field paired with a preset dropdown.
The dropdown pre-fills common values (7, 30, 90) into the input, but the user can
type any number of days they want.

## Changes

### Model (`app/models/account.rb`)
- Remove `FREQUENCY_OPTIONS` constant (or repurpose as `FREQUENCY_PRESETS` for form use only)
- Change validation from inclusion-in-list to `numericality: { only_integer: true, greater_than: 0 }, allow_nil: true`
- Update `frequency_label` to handle arbitrary values (e.g., "Every 95 days")

### Form (`app/views/accounts/_form.html.erb`)
- Replace single select with: numeric input for days + preset select that fills the input
- The select has "Not tracked" (clears input) + presets (Weekly, Monthly, Quarterly)
- The numeric input is the actual form field submitted

### Stimulus Controller (`app/javascript/controllers/frequency_preset_controller.js`)
- When preset select changes, fill the numeric input with the corresponding value
- When "Not tracked" is selected, clear the input

### Coverage Row (`app/views/shared/_coverage_row.html.erb`)
- No changes needed — already uses `frequency_label`

### Tests
- Update validation test if any exist for the inclusion constraint
- Existing coverage tests use arbitrary values (7, 30) and will continue to work

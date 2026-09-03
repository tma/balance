# Clean Expense Profile URLs

## Problem

Expense profile routes expose Rails' underscored resource name in browser URLs,
such as `/expense_profiles/1/edit`. This is less readable than the application's
existing hyphenated public URLs.

## Solution

Keep the `expense_profile` route helper and controller names unchanged while
setting the resource's public path to `expense-profiles`.

## Files

- `config/routes.rb`
- `test/controllers/expense_profiles_controller_test.rb`

## Considerations

This changes only newly generated URLs. No persisted data or application
behavior changes, and Rails route helpers remain compatible with existing code.

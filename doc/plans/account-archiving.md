# Account Archiving Feature

## Problem
Users need the ability to archive accounts they no longer actively use, while preserving all historical transaction data and maintaining the ability to import transactions for archived accounts.

## Proposed Solution
Implement account archiving following the same pattern as asset archiving, with account-specific considerations.

## Requirements
1. Archived accounts retain all transactions (untouched)
2. Imports should still work for archived accounts
3. Pending imports should prevent archiving
4. Archived accounts should be visually distinct in dropdowns (separate optgroup)

## Files to Modify

### Database
- **New migration:** Add `archived` boolean column to accounts table (default: false, not null, indexed)

### Model
- **`app/models/account.rb`:**
  - Add `active` and `archived` scopes
  - Add `archive!` and `unarchive!` methods
  - Add `has_pending_imports?` method to check for pending imports
  - Archive should fail if account has pending imports

### Routes
- **`config/routes.rb`:** Add member routes for `archive` and `unarchive` actions

### Controller
- **`app/controllers/accounts_controller.rb`:**
  - Add `archive` and `unarchive` actions
  - Update `before_action` to include new actions

### Views
- **`app/views/accounts/index.html.erb`:**
  - Separate active vs archived accounts
  - Show archived accounts in collapsible section
  - Add archive/unarchive buttons

- **`app/views/accounts/show.html.erb`:**
  - Show "Archived" badge for archived accounts
  - Show "Unarchive" button for archived accounts

### Helper
- **`app/helpers/application_helper.rb`:**
  - Update `grouped_account_options` to support showing archived accounts in a separate optgroup
  - Add parameter to control whether archived accounts are shown

### Dropdown Behavior by Location

| Location | Show Archived? | Implementation |
|----------|---------------|----------------|
| Accounts index | Yes (collapsible section) | Filter with scopes |
| Transaction form (new) | No | Pass only active accounts |
| Transaction form (edit) | Current account + active accounts | Special handling |
| Transaction filter dropdown | Yes (separate optgroup) | Include archived in separate group |
| Import target account | Yes (separate optgroup) | Include archived in separate group |

### Tests
- **`test/models/account_test.rb`:** Test scopes and archive methods
- **`test/controllers/accounts_controller_test.rb`:** Test archive/unarchive actions

## Implementation Order
1. Migration
2. Model (scopes and methods)
3. Routes
4. Controller actions
5. Helper method update
6. Views (index, show, forms)
7. Tests

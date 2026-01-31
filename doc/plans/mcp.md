# MCP Server Implementation Plan for Balance

## Money conventions (tool inputs/outputs)
- **Inputs:** use `*_cents` (integer) + optional `currency` (string, e.g. `"USD"`).
- **Outputs:** return **both**:
  - canonical integer cents fields (e.g. `amount_cents`, `net_worth_cents`)
  - human-readable formatted fields (e.g. `amount_formatted`, `net_worth_formatted`)
  - plus `currency`

This avoids float issues while still being readable for assistant/user display.

---

## Tools (with inputs/params)

### `get_net_worth`
**Purpose:** Net worth (assets - liabilities) for a point in time / period snapshot.

**Params:**
- `year` (integer, optional) — e.g. `2026`
- `month` (integer, optional, 1-12) — e.g. `1`

**Default behavior:** If `year` and `month` are omitted, default to the **previous completed month** (relative to server date).

**Returns (suggested):**
- `net_worth_cents`, `net_worth_formatted`
- `assets_total_cents`, `assets_total_formatted`
- `liabilities_total_cents`, `liabilities_total_formatted`
- `currency`
- `as_of_year`
- `as_of_month`

---

### `get_assets`
**Purpose:** List assets and current/value-at-period (depending on Balance’s data model).

**Params:**
- `year` (integer, optional) — if Balance stores historical valuations
- `month` (integer, optional, 1-12) — if Balance stores historical valuations
- `include_inactive` (boolean, optional, default: `false`)
- `type` (string, optional) — filter by asset type (e.g. `cash`, `brokerage`, `property`), if applicable

**Returns (per asset, suggested):**
- `id`
- `name`
- `type`
- `value_cents`, `value_formatted`
- `currency`
- `as_of_year` / `as_of_month` (when applicable)

---

### `get_budget_status`
**Purpose:** Show budget progress for a month.

**Params:**
- `year` (integer, optional) — default: current year
- `month` (integer, optional, 1-12) — default: current month
- `category` (string, optional) — limit to one category (or category id/name depending on app)
- `include_zeroes` (boolean, optional, default: `false`)

**Returns (suggested):**
- `year`, `month`, `currency`
- per-category:
  - `budgeted_cents`, `budgeted_formatted`
  - `spent_cents`, `spent_formatted`
  - `remaining_cents`, `remaining_formatted`
  - `pct_used`

---

### `search_transactions`
**Purpose:** Query transactions with filters (for assistants to answer questions).

**Params:**
- `year` (integer, optional)
- `month` (integer, optional, 1-12)
- `start_date` (string, optional, `YYYY-MM-DD`)
- `end_date` (string, optional, `YYYY-MM-DD`)
- `query` (string, optional) — free text match on payee/memo/notes
- `category` (string, optional) — or `category_id`
- `min_amount_cents` (integer, optional)
- `max_amount_cents` (integer, optional)
- `account` (string, optional) — or `account_id`
- `limit` (integer, optional, default: 50)
- `offset` (integer, optional, default: 0)
- `sort` (string, optional, e.g. `date_desc`, `amount_asc`)

**Returns (per transaction, suggested):**
- `id`
- `date`
- `amount_cents`, `amount_formatted`
- `currency`
- `category`
- `account`
- `payee`
- `memo`

Plus pagination info.

---

### `add_transactions`
**Purpose:** Add one or more transactions in a single call.

**Params:**
- `currency` (string, optional) — default currency if per-row not provided
- `transactions` (array, required) — each element:
  - `date` (string, required, `YYYY-MM-DD`)
  - `amount_cents` (integer, required)
  - `currency` (string, optional)
  - `category` (string, optional) — or `category_id`
  - `account` (string, optional) — or `account_id`
  - `payee` (string, optional)
  - `memo` (string, optional)
  - `cleared` (boolean, optional)
  - `external_id` (string, optional) — helpful for dedupe/import flows

**Returns (suggested):**
- `created` (array): each with `id`, `amount_cents`, `amount_formatted`, `currency`, `date`
- `errors` (array): per-item errors (index + message)

---

### `import_transactions_csv`
**Purpose:** Import transactions from a CSV export (CSV only).

**Params:**
- `csv` (string, required) — raw CSV contents
- `mapping` (object, required) — column mapping, e.g.:
  - `date_column` (string)
  - `amount_column` (string)
  - `payee_column` (string, optional)
  - `memo_column` (string, optional)
  - `category_column` (string, optional)
  - `account_column` (string, optional)
- `date_format` (string, optional) — e.g. `%Y-%m-%d` if needed
- `default_account` (string, optional)
- `default_currency` (string, optional, e.g. `"USD"`)
- `dedupe` (boolean, optional, default: `true`)
- `dry_run` (boolean, optional, default: `false`)

**Returns (suggested):**
- `currency`
- `imported_count`
- `skipped_count`
- `errors` (array)
- optionally `created` (array of `{id, date, amount_cents, amount_formatted}`)

---

### `get_spending_summary`
**Purpose:** Aggregated spending for a period.

**Params:**
- `year` (integer, optional)
- `month` (integer, optional, 1-12)
- `start_date` (string, optional, `YYYY-MM-DD`)
- `end_date` (string, optional, `YYYY-MM-DD`)
- `group_by` (string, optional, default: `category`) — e.g. `category`, `account`, `month`
- `include_income` (boolean, optional, default: `false`)

**Returns (suggested):**
- `currency`
- `totals` grouped per `group_by`, each with `total_cents`, `total_formatted`

---

### `get_insights`
**Purpose:** Lightweight insights/trends/anomalies for a period.

**Params:**
- `year` (integer, optional)
- `month` (integer, optional, 1-12)
- `start_date` (string, optional, `YYYY-MM-DD`)
- `end_date` (string, optional, `YYYY-MM-DD`)
- `sensitivity` (string, optional, e.g. `low|medium|high`)
- `limit` (integer, optional, default: 10)

**Returns (suggested):**
- `currency`
- `insights` (array) — each insight includes:
  - `type`
  - `message`
  - supporting numbers as both `*_cents` and `*_formatted` when applicable

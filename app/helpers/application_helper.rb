module ApplicationHelper
  # Generate grouped account options for select fields
  # Groups accounts by account type, displays as "Account Name - Currency"
  # Sorted by account type name, then by account name within each group
  # Archived accounts appear in a separate "Archived" optgroup
  # @param accounts [ActiveRecord::Relation] accounts to include
  # @param selected [Integer, nil] currently selected account_id
  # @return [String] HTML options grouped by account type
  def grouped_account_options(accounts, selected = nil)
    accounts_with_types = accounts.includes(:account_type)

    # Separate active and archived accounts
    active_accounts = accounts_with_types.select { |a| !a.archived? }
    archived_accounts = accounts_with_types.select { |a| a.archived? }

    groups = build_account_groups(active_accounts)

    # Add archived accounts as a separate group if any exist
    if archived_accounts.any?
      archived_options = archived_accounts.sort_by { |a| [ a.account_type.name, a.name ] }
        .map { |a| [ "#{a.name} - #{a.currency}", a.id ] }
      groups << [ "Archived", archived_options ]
    end

    grouped_options_for_select(groups, selected)
  end

  private

  def build_account_groups(accounts)
    accounts_by_type = accounts.group_by { |a| a.account_type.name }
    accounts_by_type.sort_by { |type_name, _| type_name }.map do |type_name, accts|
      [ type_name, accts.sort_by(&:name).map { |a| [ "#{a.name} - #{a.currency}", a.id ] } ]
    end
  end

  public

  # Count of imports needing attention (completed or failed)
  # Cached per request via memoization
  def imports_needing_attention_count
    @imports_needing_attention_count ||= Import.needs_attention.count
  end

  # Format currency with Swiss-style formatting: CHF 1'234.56
  # Uses apostrophe as thousand separator and the default currency code
  # Wraps output in span for privacy mode blur support
  def format_currency(amount, currency: nil, precision: 2)
    currency ||= Currency.default_code
    formatted = number_to_currency(
      amount,
      unit: "#{currency} ",
      delimiter: "'",
      separator: ".",
      precision: precision,
      format: "%u%n"
    )
    content_tag(:span, formatted, class: "currency-value")
  end

  # Format number with Swiss-style formatting (no currency): 1'234.56
  # Used when currency is shown separately
  # Wraps output in span for privacy mode blur support
  def format_amount(amount, precision: 2)
    formatted = number_to_currency(
      amount,
      unit: "",
      delimiter: "'",
      separator: ".",
      precision: precision,
      format: "%n"
    )
    content_tag(:span, formatted, class: "currency-value")
  end
end

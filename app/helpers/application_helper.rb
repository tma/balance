module ApplicationHelper
  # Generate grouped account options for select fields
  # Groups accounts by account type, displays as "Account Name - Currency"
  # Sorted by account type name, then by account name within each group
  # @param accounts [ActiveRecord::Relation] accounts to include
  # @param selected [Integer, nil] currently selected account_id
  # @return [String] HTML options grouped by account type
  def grouped_account_options(accounts, selected = nil)
    accounts_by_type = accounts.includes(:account_type).group_by { |a| a.account_type.name }
    sorted_groups = accounts_by_type.sort_by { |type_name, _| type_name }.map do |type_name, accts|
      [ type_name, accts.sort_by(&:name).map { |a| [ "#{a.name} - #{a.currency}", a.id ] } ]
    end
    grouped_options_for_select(sorted_groups, selected)
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

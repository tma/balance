module ApplicationHelper
  # Format currency with Swiss-style formatting: CHF 1'234.56
  # Uses apostrophe as thousand separator and the default currency code
  # Wraps output in span for privacy mode blur support
  def format_currency(amount, currency: nil, precision: 2)
    currency ||= Currency.default&.code || "USD"
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

module DashboardHelper
  DEFAULT_CHART_COLORS = %w[#60a5fa #4ade80 #f87171 #a78bfa #fb923c #22d3ee #e879f9 #facc15 #94a3b8 #2dd4bf].freeze

  # Color palettes for nested donut chart
  # Income: Blue-teal spectrum (cool, calming - money coming in)
  INCOME_COLORS = %w[#3b82f6 #0ea5e9 #06b6d4 #14b8a6 #10b981 #22c55e].freeze
  # Expenses: Warm diverse spectrum (distinct categories)
  EXPENSE_COLORS = %w[#8b5cf6 #ec4899 #f43f5e #f97316 #eab308 #84cc16 #06b6d4 #64748b].freeze
  SAVINGS_COLOR = "#10b981".freeze  # emerald-500

  # Build group data for donut charts from asset groups and group totals
  # Returns array of { name:, value:, pct:, color: } hashes
  def build_chart_group_data(asset_groups, group_totals)
    group_data = []
    asset_groups.each_with_index do |group, idx|
      value = group_totals[group.id] || 0
      next if value == 0
      group_data << {
        name: group.name,
        value: value,
        pct: 0,
        color: group.color || DEFAULT_CHART_COLORS[idx % DEFAULT_CHART_COLORS.length]
      }
    end

    total = group_data.sum { |g| g[:value] }
    group_data.each do |g|
      g[:pct] = total > 0 ? (g[:value].to_f / total * 100).round : 0
    end

    group_data
  end

  # Build nested donut chart data for cash flow visualization
  # Returns { income: [...], expenses: [...] } with segment data for each ring
  def build_nested_donut_data(income_by_category, expense_by_category, period_totals)
    # Build income ring data
    income_data = income_by_category.map.with_index do |cat, idx|
      {
        name: cat[:name],
        value: cat[:amount],
        color: INCOME_COLORS[idx % INCOME_COLORS.length]
      }
    end

    # Build expense ring data
    expense_data = expense_by_category.map.with_index do |cat, idx|
      {
        name: cat[:name],
        value: cat[:amount],
        color: EXPENSE_COLORS[idx % EXPENSE_COLORS.length]
      }
    end

    # Add savings slice if positive net
    savings = period_totals[:net]
    if savings > 0
      expense_data << { name: "Savings", value: savings, color: SAVINGS_COLOR }
    end

    # Calculate percentages (ensure they sum to exactly 100 to close the ring)
    income_total = income_data.sum { |d| d[:value] }
    expense_total = expense_data.sum { |d| d[:value] }

    calculate_percentages(income_data, income_total)
    calculate_percentages(expense_data, expense_total)

    { income: income_data, expenses: expense_data }
  end

  # Calculate percentages ensuring they sum to exactly 100
  def calculate_percentages(data, total)
    return if data.empty? || total <= 0

    # Calculate raw percentages
    data.each { |d| d[:pct] = (d[:value].to_f / total * 100).round(1) }

    # Adjust largest segment to ensure sum is exactly 100
    sum = data.sum { |d| d[:pct] }
    if sum != 100.0 && data.any?
      largest = data.max_by { |d| d[:value] }
      largest[:pct] += (100.0 - sum).round(1)
    end
  end

  # Generate nice tick values for Y-axis scaling
  # Returns array of tick values from 0 to a "nice" maximum
  # Always returns exactly (tick_count + 1) values for consistent grid lines
  def chart_y_ticks(max_value, tick_count = 4)
    return (0..tick_count).map { |_| 0 } if max_value <= 0

    # Find a nice step size (multiples of 1, 2, or 5 times a power of 10)
    raw_step = max_value.to_f / tick_count
    magnitude = 10 ** Math.log10(raw_step).floor
    normalized = raw_step / magnitude

    nice_step = if normalized <= 1
                  magnitude
    elsif normalized <= 2
                  2 * magnitude
    elsif normalized <= 5
                  5 * magnitude
    else
                  10 * magnitude
    end

    # Generate exactly tick_count + 1 ticks from 0 to nice_max
    (0..tick_count).map { |i| (i * nice_step).to_i }
  end

  # Format a number for Y-axis display (e.g., 1500000 -> "1.5M", 50000 -> "50K")
  def format_y_axis_value(value)
    return "0" if value == 0

    if value >= 1_000_000
      formatted = value.to_f / 1_000_000
      formatted == formatted.to_i ? "#{formatted.to_i}M" : "#{formatted.round(1)}M"
    elsif value >= 1_000
      formatted = value.to_f / 1_000
      formatted == formatted.to_i ? "#{formatted.to_i}K" : "#{formatted.round(1)}K"
    else
      value.to_s
    end
  end
end

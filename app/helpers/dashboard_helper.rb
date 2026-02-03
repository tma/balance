module DashboardHelper
  DEFAULT_CHART_COLORS = %w[#60a5fa #4ade80 #f87171 #a78bfa #fb923c #22d3ee #e879f9 #facc15 #94a3b8 #2dd4bf].freeze

  # Color scheme options for category donut chart
  COLOR_SCHEMES = {
    # Option A: Blue for income, red/rose for expenses (matches summary donut)
    blue_red: {
      income: %w[#3b82f6 #60a5fa #93c5fd #bfdbfe #dbeafe #eff6ff],
      expense: %w[#e11d48 #f43f5e #fb7185 #fda4af #fecdd3 #ffe4e6]
    },
    # Option B: Blue for income, red/rose for expenses (more saturated)
    blue_red_bold: {
      income: %w[#1d4ed8 #2563eb #3b82f6 #60a5fa #93c5fd #bfdbfe],
      expense: %w[#be123c #e11d48 #f43f5e #fb7185 #fda4af #fecdd3]
    },
    # Option C: Blue-teal for income, red-orange for expenses
    blue_warm: {
      income: %w[#0ea5e9 #38bdf8 #7dd3fc #60a5fa #93c5fd #bae6fd],
      expense: %w[#dc2626 #ef4444 #f87171 #fb923c #fdba74 #fed7aa]
    },
    # Option D: Monochromatic pastels (original)
    pastel_mono: {
      income: %w[#93c5fd #7dd3fc #5eead4 #6ee7b7 #86efac #a7f3d0],
      expense: %w[#fda4af #f9a8d4 #f0abfc #d8b4fe #c4b5fd #a5b4fc]
    }
  }.freeze

  SAVINGS_COLOR = "#10b981".freeze  # emerald-500

  # Get colors for a specific scheme
  def category_colors(type, scheme = :pastel_mono)
    COLOR_SCHEMES[scheme][type] || COLOR_SCHEMES[:pastel_mono][type]
  end

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
  # Limits to top 5 categories + "Other" for the rest
  def build_nested_donut_data(income_by_category, expense_by_category, period_totals, scheme: :blue_red)
    income_colors = category_colors(:income, scheme)
    expense_colors = category_colors(:expense, scheme)

    # Build income ring data (top 6 + Other)
    income_data = summarize_to_top_categories(income_by_category, income_colors, 6, other_color: "#a5b4fc")

    # Build expense ring data (top 6 + Other)
    expense_data = summarize_to_top_categories(expense_by_category, expense_colors, 6, other_color: "#fecdd3")

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

  # Summarize categories to top N + "Other"
  # Categories below min_pct threshold are always grouped into "Other"
  def summarize_to_top_categories(categories, colors, limit, min_pct: 4.0, other_color: "#94a3b8")
    return [] if categories.empty?

    total = categories.sum { |c| c[:amount] }
    return [] if total <= 0

    # Split into above/below threshold
    above_threshold = []
    below_threshold = []

    categories.each do |cat|
      pct = (cat[:amount].to_f / total * 100)
      if pct >= min_pct
        above_threshold << cat
      else
        below_threshold << cat
      end
    end

    # Sort by amount and take top N from those above threshold
    sorted = above_threshold.sort_by { |c| -c[:amount] }
    top = sorted.take(limit)
    rest = sorted.drop(limit) + below_threshold

    data = top.map.with_index do |cat, idx|
      {
        name: cat[:name],
        value: cat[:amount],
        color: colors[idx % colors.length]
      }
    end

    if rest.any?
      other_value = rest.sum { |c| c[:amount] }
      data << { name: "Other", value: other_value, color: other_color }
    end

    data
  end

  # Calculate percentages ensuring they sum to exactly 100
  def calculate_percentages(data, total)
    return if data.empty?

    # Handle zero total - set all percentages to 0
    if total <= 0
      data.each { |d| d[:pct] = 0 }
      return
    end

    # Calculate raw percentages
    data.each { |d| d[:pct] = (d[:value].to_f / total * 100).round }

    # Adjust largest segment to ensure sum is exactly 100
    sum = data.sum { |d| d[:pct] }
    if sum != 100 && data.any?
      largest = data.max_by { |d| d[:value] }
      largest[:pct] += (100 - sum)
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

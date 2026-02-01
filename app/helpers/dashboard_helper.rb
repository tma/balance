module DashboardHelper
  DEFAULT_CHART_COLORS = %w[#60a5fa #4ade80 #f87171 #a78bfa #fb923c #22d3ee #e879f9 #facc15 #94a3b8 #2dd4bf].freeze

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

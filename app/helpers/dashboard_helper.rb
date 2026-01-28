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
end

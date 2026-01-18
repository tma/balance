class AddColorToAssetGroups < ActiveRecord::Migration[8.1]
  DEFAULT_COLORS = %w[#60a5fa #4ade80 #f87171 #a78bfa #fb923c #22d3ee #e879f9 #facc15 #94a3b8 #2dd4bf]

  def up
    add_column :asset_groups, :color, :string

    # Backfill existing groups with colors
    AssetGroup.reset_column_information
    AssetGroup.order(:position, :id).each_with_index do |group, idx|
      group.update_column(:color, DEFAULT_COLORS[idx % DEFAULT_COLORS.length])
    end
  end

  def down
    remove_column :asset_groups, :color
  end
end

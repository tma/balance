class BackfillAndEnforcePositions < ActiveRecord::Migration[8.1]
  def up
    # Backfill asset_groups positions
    execute <<-SQL
      UPDATE asset_groups
      SET position = (
        SELECT COUNT(*) FROM asset_groups ag2 
        WHERE ag2.id < asset_groups.id
      )
      WHERE position IS NULL OR position = 0
    SQL

    # Backfill assets positions within each group
    execute <<-SQL
      UPDATE assets
      SET position = (
        SELECT COUNT(*) FROM assets a2 
        WHERE a2.asset_group_id = assets.asset_group_id 
        AND a2.id < assets.id
      )
      WHERE position IS NULL OR position = 0
    SQL

    # Make columns non-nullable
    change_column_null :asset_groups, :position, false
    change_column_null :assets, :position, false
  end

  def down
    change_column_null :asset_groups, :position, true
    change_column_null :assets, :position, true
  end
end

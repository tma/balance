class UpdateBudgetsForRecurring < ActiveRecord::Migration[8.1]
  def up
    # Add new columns
    add_column :budgets, :period, :string, default: "monthly", null: false
    add_column :budgets, :start_date, :date

    # Migrate existing data: set start_date from month/year, keep most recent per category
    execute <<-SQL
      UPDATE budgets
      SET start_date = date(year || '-' || printf('%02d', month) || '-01')
    SQL

    # For duplicate categories, keep only the most recent (highest year, then month)
    execute <<-SQL
      DELETE FROM budgets
      WHERE id NOT IN (
        SELECT id FROM (
          SELECT id, ROW_NUMBER() OVER (
            PARTITION BY category_id
            ORDER BY year DESC, month DESC
          ) as rn
          FROM budgets
        ) ranked
        WHERE rn = 1
      )
    SQL

    # Remove old columns
    remove_column :budgets, :month
    remove_column :budgets, :year

    # Remove the existing non-unique index and add a unique one
    remove_index :budgets, :category_id, if_exists: true
    add_index :budgets, :category_id, unique: true
  end

  def down
    # Remove unique index
    remove_index :budgets, :category_id, if_exists: true

    # Add back old columns
    add_column :budgets, :month, :integer
    add_column :budgets, :year, :integer

    # Migrate data back from start_date
    execute <<-SQL
      UPDATE budgets
      SET month = CAST(strftime('%m', start_date) AS INTEGER),
          year = CAST(strftime('%Y', start_date) AS INTEGER)
      WHERE start_date IS NOT NULL
    SQL

    # Set defaults for any null values
    execute <<-SQL
      UPDATE budgets
      SET month = #{Date.current.month}, year = #{Date.current.year}
      WHERE month IS NULL OR year IS NULL
    SQL

    # Remove new columns
    remove_column :budgets, :period
    remove_column :budgets, :start_date

    # Re-add the non-unique index
    add_index :budgets, :category_id
  end
end

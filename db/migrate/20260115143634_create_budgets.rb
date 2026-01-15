class CreateBudgets < ActiveRecord::Migration[8.1]
  def change
    create_table :budgets do |t|
      t.references :category, null: false, foreign_key: true
      t.decimal :amount
      t.integer :month
      t.integer :year

      t.timestamps
    end
  end
end

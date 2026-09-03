class CreateExpenseProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :expense_profiles do |t|
      t.references :category, null: false, foreign_key: true
      t.string :merchant_pattern, null: false
      t.string :essentiality
      t.string :cadence
      t.string :source, null: false, default: "machine"
      t.string :status, null: false, default: "suggested"
      t.string :recurrence_confidence
      t.decimal :confirmed_amount, precision: 15, scale: 2
      t.integer :occurrence_count, null: false, default: 0
      t.date :first_seen_on
      t.date :last_seen_on
      t.decimal :median_amount, precision: 15, scale: 2
      t.decimal :amount_cv, precision: 8, scale: 4
      t.decimal :interval_cv, precision: 8, scale: 4
      t.string :detected_cadence
      t.datetime :detected_at
      t.datetime :confirmed_at
      t.text :review_flags

      t.timestamps
    end

    add_index :expense_profiles, [ :merchant_pattern, :category_id ], unique: true
    add_check_constraint :expense_profiles,
                         "essentiality IS NULL OR essentiality IN ('essential', 'discretionary', 'excluded')",
                         name: "expense_profiles_essentiality"
    add_check_constraint :expense_profiles,
                         "cadence IS NULL OR cadence IN ('monthly', 'quarterly', 'semiannual', 'annual')",
                         name: "expense_profiles_cadence"
    add_check_constraint :expense_profiles,
                         "source IN ('human', 'machine')",
                         name: "expense_profiles_source"
    add_check_constraint :expense_profiles,
                         "status IN ('suggested', 'confirmed', 'dismissed', 'inactive')",
                         name: "expense_profiles_status"
    add_check_constraint :expense_profiles,
                         "recurrence_confidence IS NULL OR recurrence_confidence IN ('high', 'medium', 'low')",
                         name: "expense_profiles_recurrence_confidence"
  end
end

class AddTrailingAnnualAmountToExpenseProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :expense_profiles, :trailing_annual_amount, :decimal, precision: 15, scale: 2
  end
end

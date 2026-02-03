class AddExpectedTransactionFrequencyToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :expected_transaction_frequency, :integer
  end
end

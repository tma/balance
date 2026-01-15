class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.string :name
      t.references :account_type, null: false, foreign_key: true
      t.decimal :balance
      t.string :currency

      t.timestamps
    end
  end
end

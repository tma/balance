class CreatePositionValuations < ActiveRecord::Migration[8.1]
  def change
    create_table :position_valuations do |t|
      t.references :broker_position, null: false, foreign_key: true
      t.date :date, null: false
      t.decimal :quantity, precision: 15, scale: 4
      t.decimal :value, precision: 15, scale: 2
      t.string :currency, null: false

      t.timestamps
    end

    add_index :position_valuations, [ :broker_position_id, :date ], unique: true
  end
end

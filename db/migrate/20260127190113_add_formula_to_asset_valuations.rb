class AddFormulaToAssetValuations < ActiveRecord::Migration[8.1]
  def change
    add_column :asset_valuations, :formula, :string
  end
end

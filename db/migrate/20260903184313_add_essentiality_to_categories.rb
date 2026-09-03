class AddEssentialityToCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :categories, :essentiality, :string
    add_check_constraint :categories,
                         "essentiality IS NULL OR essentiality IN ('essential', 'discretionary', 'mixed', 'excluded')",
                         name: "categories_essentiality"
  end
end

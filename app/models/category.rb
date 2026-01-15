class Category < ApplicationRecord
  has_many :transactions, dependent: :restrict_with_error
  has_many :budgets, dependent: :destroy

  enum :category_type, { income: "income", expense: "expense" }

  validates :name, presence: true, uniqueness: { scope: :category_type }
  validates :category_type, presence: true
end

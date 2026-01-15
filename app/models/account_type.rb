class AccountType < ApplicationRecord
  has_many :accounts, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
end

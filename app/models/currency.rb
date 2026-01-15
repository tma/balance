class Currency < ApplicationRecord
  validates :code, presence: true, uniqueness: true, length: { is: 3 }
  validates :code, format: { with: /\A[A-Z]{3}\z/, message: "must be 3 uppercase letters (ISO 4217)" }
end

class AssetType < ApplicationRecord
  has_many :assets, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true

  attribute :is_liability, :boolean, default: false
end

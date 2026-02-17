class CategoryPattern < ApplicationRecord
  belongs_to :category

  enum :source, { human: "human", machine: "machine" }

  validates :pattern, presence: true
  validates :pattern, uniqueness: { scope: :source }

  scope :by_match_count, -> { order(match_count: :desc) }

  after_commit :schedule_category_embedding_update

  def increment_match_count!
    increment!(:match_count)
  end

  private

  def schedule_category_embedding_update
    CategoryEmbeddingJob.perform_later(category_id)
  end
end

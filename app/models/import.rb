class Import < ApplicationRecord
  belongs_to :account
  has_many :transactions, dependent: :nullify

  # Status constants
  STATUSES = %w[pending processing completed failed done].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :original_filename, presence: true
  validates :file_content_type, presence: true
  validates :file_data, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :pending, -> { where(status: "pending") }
  scope :processing, -> { where(status: "processing") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :done, -> { where(status: "done") }

  def pending?
    status == "pending"
  end

  def processing?
    status == "processing"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def done?
    status == "done"
  end

  def pdf?
    file_content_type == "application/pdf"
  end

  def csv?
    file_content_type.in?(%w[text/csv text/plain application/csv])
  end

  def extracted_transactions
    return [] if extracted_data.blank?
    JSON.parse(extracted_data, symbolize_names: true)
  rescue JSON::ParserError
    []
  end

  def extracted_transactions=(data)
    self.extracted_data = data.to_json
  end

  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end

  def mark_processing!
    update!(status: "processing", started_at: Time.current, progress: nil)
  end

  def update_progress!(current, total)
    update_column(:progress, "#{current}/#{total}")
  end

  def progress_info
    return nil if progress.blank?
    current, total = progress.split("/").map(&:to_i)
    { current: current, total: total, percent: (current.to_f / total * 100).round }
  rescue
    nil
  end

  def mark_completed!(transactions_data, count: 0)
    update!(
      status: "completed",
      extracted_data: transactions_data.to_json,
      transactions_count: count,
      completed_at: Time.current
    )
  end

  def mark_failed!(message)
    update!(
      status: "failed",
      error_message: message,
      completed_at: Time.current
    )
  end

  # Returns the most recent month from extracted transactions
  # @return [Date, nil] First day of the most recent transaction month, or nil
  def transaction_month
    return nil unless completed? || done?

    dates = extracted_transactions.map { |t| parse_transaction_date(t[:date]) }.compact
    return nil if dates.empty?

    most_recent = dates.max
    most_recent.beginning_of_month
  end

  private

  def parse_transaction_date(date_value)
    case date_value
    when Date
      date_value
    when String
      Date.parse(date_value)
    end
  rescue ArgumentError, TypeError
    nil
  end
end

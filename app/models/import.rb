class Import < ApplicationRecord
  include Turbo::Broadcastable

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
  scope :needs_attention, -> { where(status: %w[pending processing completed failed]) }

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
    update!(
      status: "processing",
      started_at: Time.current,
      progress: nil,
      extracted_count: 0,
      progress_message: "Starting extraction"
    )
    broadcast_status_update
  end

  def update_progress!(current, total, extracted_count: nil, message: nil)
    updates = { progress: "#{current}/#{total}" }
    updates[:extracted_count] = extracted_count unless extracted_count.nil?
    updates[:progress_message] = message if message
    update_columns(updates)
    # Reload attributes so broadcast uses fresh data
    reload
    broadcast_status_update
  end

  def progress_info
    return nil if progress.blank?
    current, total = progress.split("/").map(&:to_i)
    { current: current, total: total, percent: (current.to_f / total * 100).round }
  rescue
    nil
  end

  def mark_completed!(transactions_data)
    update!(
      status: "completed",
      extracted_data: transactions_data.to_json,
      completed_at: Time.current
    )
    broadcast_status_complete
  end

  def mark_failed!(message)
    update!(
      status: "failed",
      error_message: message,
      completed_at: Time.current
    )
    broadcast_status_complete
  end

  # Returns the most recent month from transactions
  # For done imports, uses committed transactions; for completed, uses extracted data
  # @return [Date, nil] First day of the most recent transaction month, or nil
  def transaction_month
    return nil unless completed? || done?

    dates = if done? && transactions.any?
      transactions.pluck(:date).compact
    else
      extracted_transactions.map { |t| parse_transaction_date(t[:date]) }.compact
    end

    return nil if dates.empty?

    most_recent = dates.max
    most_recent.beginning_of_month
  end

  private

  def broadcast_status_update
    Turbo::StreamsChannel.broadcast_stream_to(
      self,
      content: turbo_stream_content
    )
  end

  def turbo_stream_content
    ApplicationController.render(
      partial: "imports/status_stream",
      locals: { import: self }
    )
  end

  def broadcast_status_complete
    broadcast_action_to(
      self,
      action: :replace,
      target: "import_status",
      html: '<div id="import_status" data-status-complete="true"></div>'
    )
  end

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

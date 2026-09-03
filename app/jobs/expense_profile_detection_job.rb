class ExpenseProfileDetectionJob < ApplicationJob
  queue_as :default

  def perform(through = nil)
    data_complete_through = Date.strptime(through, "%Y-%m") if through.present?
    period = CostOfLivingPeriodService.new(data_complete_through: data_complete_through).call
    ExpenseProfileDetectionService.new(period: period).call
  end
end

class ExpenseProfileImportAnalysisJob < ApplicationJob
  queue_as :default

  def perform(category_ids)
    category_ids.each do |category_id|
      CategoryPatternExtractionJob.perform_now(category_id: category_id)
    end
    ExpenseProfileDetectionService.new.call
  end
end

class ExpenseProfilesController < ApplicationController
  before_action :set_expense_profile, only: %i[ edit update dismiss deactivate ]

  def edit
  end

  def update
    @expense_profile.merchant_pattern = expense_profile_params[:merchant_pattern] if expense_profile_params[:merchant_pattern].present?
    cadence = expense_profile_params[:cadence].presence
    amount = cadence ? (expense_profile_params[:confirmed_amount].presence || @expense_profile.median_amount) : nil
    @expense_profile.confirm!(
      essentiality: expense_profile_params[:essentiality],
      cadence: cadence,
      confirmed_amount: amount
    )

    redirect_to cost_of_living_path, notice: "Expense profile confirmed.", status: :see_other
  rescue ActiveRecord::RecordInvalid
    redirect_to cost_of_living_path,
                alert: @expense_profile.errors.full_messages.to_sentence,
                status: :see_other
  end

  def dismiss
    @expense_profile.update!(status: "dismissed")
    redirect_to cost_of_living_path, notice: "Suggestion dismissed.", status: :see_other
  end

  def deactivate
    @expense_profile.update!(status: "inactive", review_flags: [])
    redirect_to cost_of_living_path, notice: "Expense profile deactivated.", status: :see_other
  end

  def detect
    through = validated_through
    ExpenseProfileDetectionJob.perform_later(through)
    redirect_to cash_flow_path(view: "cost_of_living", through: through),
                notice: "Grouped expense-stream analysis has started.",
                status: :see_other
  end

  def bulk_confirm
    projection = CostOfLivingProjectionService.new.call
    profiles = projection[:bulk_eligible_profiles]
    profiles.each do |profile|
      profile.confirm!(
        essentiality: profile.essentiality,
        cadence: profile.detected_cadence,
        confirmed_amount: profile.median_amount
      )
    end

    redirect_to cost_of_living_path,
                notice: "#{profiles.size} high-confidence profiles confirmed.",
                status: :see_other
  end

  private

  def set_expense_profile
    @expense_profile = ExpenseProfile.find(params.expect(:id))
  end

  def expense_profile_params
    params.expect(expense_profile: [ :merchant_pattern, :essentiality, :cadence, :confirmed_amount ])
  end

  def cost_of_living_path
    cash_flow_path(view: "cost_of_living")
  end

  def validated_through
    return if params[:through].blank?

    month = Date.strptime(params[:through], "%Y-%m")
    raise Date::Error if month >= Date.current.beginning_of_month

    month.strftime("%Y-%m")
  rescue Date::Error
    raise ActionController::BadRequest, "Invalid Cost of Living month"
  end
end

require "test_helper"

class ExpenseProfilesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @profile = expense_profiles(:whole_foods)
  end

  test "uses hyphenated public URLs" do
    assert_equal "/expense-profiles/#{@profile.id}/edit", edit_expense_profile_path(@profile)
  end

  test "confirms a suggested profile" do
    @profile.update!(status: "suggested", essentiality: nil, cadence: nil, confirmed_amount: nil)

    patch expense_profile_url(@profile), params: {
      expense_profile: {
        merchant_pattern: @profile.merchant_pattern,
        essentiality: "essential",
        cadence: "monthly",
        confirmed_amount: 155
      }
    }

    assert_redirected_to cash_flow_url(view: "cost_of_living")
    assert @profile.reload.status_confirmed?
    assert_equal 155.to_d, @profile.confirmed_amount
  end

  test "edits a confirmed profile" do
    get edit_expense_profile_url(@profile)

    assert_response :success
    assert_select "input[name='expense_profile[merchant_pattern]']"
    assert_select "select[name='expense_profile[cadence]']"
  end

  test "updates confirmed profile values" do
    patch expense_profile_url(@profile), params: {
      expense_profile: {
        merchant_pattern: "Whole Foods Market",
        essentiality: "essential",
        cadence: "monthly",
        confirmed_amount: 175
      }
    }

    assert_redirected_to cash_flow_url(view: "cost_of_living")
    assert_equal "Whole Foods Market", @profile.reload.merchant_pattern
    assert_equal 175.to_d, @profile.confirmed_amount
  end

  test "dismisses a suggestion" do
    @profile.update!(status: "suggested", essentiality: nil, cadence: nil, confirmed_amount: nil)

    patch dismiss_expense_profile_url(@profile)

    assert_redirected_to cash_flow_url(view: "cost_of_living")
    assert @profile.reload.status_dismissed?
  end

  test "refresh queues grouped analysis" do
    assert_enqueued_with(job: ExpenseProfileDetectionJob, args: [ "2026-06" ]) do
      post detect_expense_profiles_url(through: "2026-06")
    end

    assert_redirected_to cash_flow_url(view: "cost_of_living", through: "2026-06")
  end

  test "deactivates a confirmed profile" do
    patch deactivate_expense_profile_url(@profile)

    assert_redirected_to cash_flow_url(view: "cost_of_living")
    assert @profile.reload.status_inactive?
  end
end

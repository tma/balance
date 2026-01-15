require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "should get cash_flow" do
    get cash_flow_url
    assert_response :success
  end

  test "should get net_worth" do
    get net_worth_url
    assert_response :success
  end

  test "root should redirect to cash_flow" do
    get root_url
    assert_response :success
  end
end

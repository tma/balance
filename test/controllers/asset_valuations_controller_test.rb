require "test_helper"

class AssetValuationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @asset = assets(:house)
    @current_month_end = Date.current.end_of_month
  end

  test "should get edit" do
    get update_valuations_path
    assert_response :success
  end

  test "should update asset valuations" do
    original_value = @asset.value
    new_value = original_value + 100

    patch update_valuations_path, params: {
      valuations: { @asset.id => { @current_month_end.iso8601 => new_value } }
    }

    assert_redirected_to update_valuations_path
    valuation = @asset.asset_valuations.find_by(date: @current_month_end)
    assert_equal new_value, valuation.value
  end

  test "should not update when value unchanged" do
    # Create an existing valuation first
    @asset.asset_valuations.create!(date: @current_month_end, value: @asset.value)
    original_count = AssetValuation.count

    patch update_valuations_path, params: {
      valuations: { @asset.id => { @current_month_end.iso8601 => @asset.value } }
    }

    assert_redirected_to update_valuations_path
    # No new valuation should be created since value didn't change
    assert_equal original_count, AssetValuation.count
  end

  test "should skip blank values" do
    original_count = AssetValuation.count

    patch update_valuations_path, params: {
      valuations: { @asset.id => { @current_month_end.iso8601 => "" } }
    }

    assert_redirected_to update_valuations_path
    assert_equal original_count, AssetValuation.count
  end

  test "should create valuations for multiple months" do
    last_month_end = (Date.current - 1.month).end_of_month

    patch update_valuations_path, params: {
      valuations: {
        @asset.id => {
          @current_month_end.iso8601 => 100_000,
          last_month_end.iso8601 => 95_000
        }
      }
    }

    assert_redirected_to update_valuations_path
    assert_equal 100_000, @asset.asset_valuations.find_by(date: @current_month_end).value
    assert_equal 95_000, @asset.asset_valuations.find_by(date: last_month_end).value
  end
end

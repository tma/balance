require "test_helper"

class AssetValuationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @asset = assets(:house)
  end

  test "should get edit" do
    get update_valuations_path
    assert_response :success
  end

  test "should update asset valuations" do
    original_value = @asset.value
    new_value = original_value + 100

    patch update_valuations_path, params: {
      assets: { @asset.id => new_value }
    }

    assert_redirected_to update_valuations_path
    @asset.reload
    assert_equal new_value, @asset.value
  end

  test "should not update when value unchanged" do
    original_count = AssetValuation.count

    patch update_valuations_path, params: {
      assets: { @asset.id => @asset.value }
    }

    assert_redirected_to update_valuations_path
    # No new valuation should be created since value didn't change
    assert_equal original_count, AssetValuation.count
  end

  test "should skip blank values" do
    original_value = @asset.value

    patch update_valuations_path, params: {
      assets: { @asset.id => "" }
    }

    assert_redirected_to update_valuations_path
    @asset.reload
    assert_equal original_value, @asset.value
  end
end

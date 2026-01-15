require "test_helper"

class Admin::AssetTypesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @asset_type = asset_types(:property)
  end

  test "should get index" do
    get admin_asset_types_url
    assert_response :success
  end

  test "should get new" do
    get new_admin_asset_type_url
    assert_response :success
  end

  test "should create asset_type" do
    assert_difference("AssetType.count") do
      post admin_asset_types_url, params: { asset_type: { is_liability: false, name: "investment" } }
    end

    assert_redirected_to admin_asset_type_url(AssetType.last)
  end

  test "should show asset_type" do
    get admin_asset_type_url(@asset_type)
    assert_response :success
  end

  test "should get edit" do
    get edit_admin_asset_type_url(@asset_type)
    assert_response :success
  end

  test "should update asset_type" do
    patch admin_asset_type_url(@asset_type), params: { asset_type: { is_liability: @asset_type.is_liability, name: @asset_type.name } }
    assert_redirected_to admin_asset_type_url(@asset_type)
  end

  test "should destroy asset_type" do
    # Create a new asset type to destroy (not used by assets)
    asset_type = AssetType.create!(name: "vehicle", is_liability: false)
    assert_difference("AssetType.count", -1) do
      delete admin_asset_type_url(asset_type)
    end

    assert_redirected_to admin_asset_types_url
  end
end

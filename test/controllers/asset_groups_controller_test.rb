require "test_helper"

class AssetGroupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @asset_group = asset_groups(:real_estate)
  end

  test "should get index" do
    get asset_groups_url
    assert_response :success
  end

  test "should get new" do
    get new_asset_group_url
    assert_response :success
  end

  test "should create asset_group" do
    assert_difference("AssetGroup.count") do
      post asset_groups_url, params: { asset_group: { name: "New Group", description: "Test" } }
    end

    assert_redirected_to asset_group_url(AssetGroup.last)
  end

  test "should show asset_group" do
    get asset_group_url(@asset_group)
    assert_response :success
  end

  test "should get edit" do
    get edit_asset_group_url(@asset_group)
    assert_response :success
  end

  test "should update asset_group" do
    patch asset_group_url(@asset_group), params: { asset_group: { name: "Updated Name" } }
    assert_redirected_to asset_group_url(@asset_group)
  end

  test "should destroy asset_group without assets" do
    empty_group = AssetGroup.create!(name: "Empty Group")
    assert_difference("AssetGroup.count", -1) do
      delete asset_group_url(empty_group)
    end

    assert_redirected_to asset_groups_url
  end
end

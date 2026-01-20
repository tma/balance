require "test_helper"

class AssetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @asset = assets(:investment_property) # Asset without broker positions
    @asset_with_broker = assets(:house) # Asset with broker positions
    @asset_group = asset_groups(:real_estate)
  end

  test "should get index" do
    get assets_url
    assert_response :success
  end

  test "should get new" do
    get new_asset_url
    assert_response :success
  end

  test "should create asset" do
    assert_difference("Asset.count") do
      post assets_url, params: { asset: { asset_type_id: @asset.asset_type_id, asset_group_id: @asset_group.id, currency: @asset.currency, name: "New Asset", notes: "Test notes", value: 10000.00 } }
    end

    assert_redirected_to asset_url(Asset.last)
  end

  test "should show asset" do
    get asset_url(@asset)
    assert_response :success
  end

  test "should get edit" do
    get edit_asset_url(@asset)
    assert_response :success
  end

  test "should update asset" do
    patch asset_url(@asset), params: { asset: { asset_type_id: @asset.asset_type_id, asset_group_id: @asset_group.id, currency: @asset.currency, name: @asset.name, notes: @asset.notes, value: @asset.value } }
    assert_redirected_to asset_url(@asset)
  end

  test "should destroy asset" do
    assert_difference("Asset.count", -1) do
      delete asset_url(@asset)
    end

    assert_redirected_to assets_url
  end

  test "should archive asset" do
    assert_not @asset.archived?
    patch archive_asset_url(@asset)
    assert_redirected_to assets_url
    assert @asset.reload.archived?
  end

  test "should unarchive asset" do
    @asset.update!(archived: true)
    patch unarchive_asset_url(@asset)
    assert_redirected_to assets_url
    assert_not @asset.reload.archived?
  end

  test "should not archive asset with open broker positions" do
    assert @asset_with_broker.has_broker?

    patch archive_asset_url(@asset_with_broker)
    assert_redirected_to assets_url
    assert_not @asset_with_broker.reload.archived?
    assert_match /Cannot archive/, flash[:alert]
  end
end

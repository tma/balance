require "test_helper"

class AssetTest < ActiveSupport::TestCase
  setup do
    @asset = assets(:investment_property) # Asset without broker positions
    @asset_with_broker = assets(:house) # Asset with broker positions (from fixtures)
  end

  test "active scope returns non-archived assets" do
    assert_includes Asset.active, @asset
    @asset.update!(archived: true)
    assert_not_includes Asset.active, @asset
  end

  test "archived scope returns archived assets" do
    assert_not_includes Asset.archived, @asset
    @asset.update!(archived: true)
    assert_includes Asset.archived, @asset
  end

  test "archive! sets archived to true" do
    assert_not @asset.archived?
    @asset.archive!
    assert @asset.archived?
  end

  test "unarchive! sets archived to false" do
    @asset.update!(archived: true)
    assert @asset.archived?
    @asset.unarchive!
    assert_not @asset.archived?
  end

  test "archive! raises error for asset with open broker positions" do
    assert @asset_with_broker.has_broker?
    assert_raises(ActiveRecord::RecordInvalid) do
      @asset_with_broker.archive!
    end
    assert_not @asset_with_broker.reload.archived?
  end

  test "archive! succeeds for asset with closed broker positions" do
    # Close all broker positions for this asset
    @asset_with_broker.broker_positions.each do |pos|
      pos.update!(closed_at: Time.current)
    end

    assert_not @asset_with_broker.has_broker?
    @asset_with_broker.archive!
    assert @asset_with_broker.archived?
  end

  test "new assets default to not archived" do
    asset = Asset.new(
      name: "Test Asset",
      asset_type: asset_types(:property),
      asset_group: asset_groups(:real_estate),
      currency: "USD",
      value: 1000
    )
    assert_not asset.archived?
  end
end

require "test_helper"

class AssetGroupTest < ActiveSupport::TestCase
  test "validates presence of name" do
    group = AssetGroup.new(name: nil)
    assert_not group.valid?
    assert_includes group.errors[:name], "can't be blank"
  end

  test "valid asset group" do
    group = AssetGroup.new(name: "Test Group")
    assert group.valid?
  end

  test "can have description" do
    group = AssetGroup.new(name: "Test Group", description: "A test description")
    assert group.valid?
    assert_equal "A test description", group.description
  end

  test "calculates net value by currency" do
    group = asset_groups(:real_estate)
    net_values = group.net_value_by_currency

    # House is 250000 (asset), Mortgage is 200000 (liability)
    # Net should be 250000 - 200000 = 50000
    assert_equal 50000, net_values["USD"]
  end

  test "cannot destroy group with assets" do
    group = asset_groups(:real_estate)
    assert_not group.destroy
    assert_includes group.errors[:base], "Cannot delete record because dependent assets exist"
  end
end

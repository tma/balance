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

  test "sync_from_broker_positions creates zero valuation for current month when already zero" do
    asset = Asset.create!(
      name: "Closed Broker Asset",
      asset_type: asset_types(:property),
      asset_group: asset_groups(:real_estate),
      currency: "USD",
      value: 0
    )
    asset.asset_valuations.destroy_all

    broker_connections(:one).broker_positions.create!(
      symbol: "CLOSED_TEST",
      description: "Closed Test",
      currency: "USD",
      last_value: 0,
      last_quantity: 0,
      closed_at: Time.current,
      asset: asset
    )

    assert_difference "AssetValuation.count", 1 do
      asset.sync_from_broker_positions!
    end

    valuation = asset.asset_valuations.find_by(date: Date.current.end_of_month)
    assert_equal 0, valuation.value
  end

  test "sync_from_broker_positions uses broker default valuation before external conversion" do
    asset = Asset.create!(
      name: "Broker FX Asset",
      asset_type: asset_types(:property),
      asset_group: asset_groups(:real_estate),
      currency: "USD",
      value: 0
    )
    asset.asset_valuations.destroy_all

    position = broker_connections(:one).broker_positions.create!(
      symbol: "EUR_DEFAULT_VALUE_TEST",
      description: "EUR Default Value Test",
      currency: "EUR",
      last_value: 500,
      last_quantity: 5,
      asset: asset
    )
    position.position_valuations.create!(
      date: Date.current,
      quantity: 5,
      value: 500,
      currency: "EUR",
      fx_rate_to_base: 1.2,
      ibkr_base_currency: "USD"
    )

    original_convert = ExchangeRateService.method(:convert)
    ExchangeRateService.define_singleton_method(:convert) { |_amount, _from, _to, date:| nil }

    assert_difference "AssetValuation.count", 1 do
      asset.sync_from_broker_positions!
    end

    valuation = asset.asset_valuations.find_by(date: Date.current.end_of_month)
    assert_equal 600, asset.reload.value
    assert_equal 600, valuation.value
  ensure
    ExchangeRateService.define_singleton_method(:convert) do |*args, **kwargs, &block|
      original_convert.call(*args, **kwargs, &block)
    end
  end

  test "sync_from_broker_positions keeps value when currency conversion fails" do
    asset = Asset.create!(
      name: "FX Failure Asset",
      asset_type: asset_types(:property),
      asset_group: asset_groups(:real_estate),
      currency: "USD",
      value: 1000
    )
    asset.asset_valuations.destroy_all

    broker_connections(:one).broker_positions.create!(
      symbol: "EUR_TEST",
      description: "EUR Test",
      currency: "EUR",
      last_value: 500,
      last_quantity: 5,
      asset: asset
    )

    original_convert = ExchangeRateService.method(:convert)
    ExchangeRateService.define_singleton_method(:convert) { |_amount, _from, _to, date:| nil }

    assert_no_difference "AssetValuation.count" do
      asset.sync_from_broker_positions!
    end

    assert_equal 1000, asset.reload.value
  ensure
    ExchangeRateService.define_singleton_method(:convert) do |*args, **kwargs, &block|
      original_convert.call(*args, **kwargs, &block)
    end
  end
end

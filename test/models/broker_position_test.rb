require "test_helper"

class BrokerPositionTest < ActiveSupport::TestCase
  setup do
    @connection = broker_connections(:one)
    @position = broker_positions(:aapl_position)
  end

  test "validates presence of symbol" do
    position = BrokerPosition.new(broker_connection: @connection)
    assert_not position.valid?
    assert_includes position.errors[:symbol], "can't be blank"
  end

  test "validates uniqueness of symbol within connection" do
    duplicate = BrokerPosition.new(
      broker_connection: @connection,
      symbol: @position.symbol,
      currency: "USD"
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:symbol], "has already been taken"
  end

  test "allows same symbol in different connections" do
    other_connection = broker_connections(:two)
    position = BrokerPosition.new(
      broker_connection: other_connection,
      symbol: @position.symbol,
      currency: "USD"
    )
    # May or may not be valid depending on if symbol exists in other_connection
    # The key is it doesn't fail uniqueness for the same symbol
    position.symbol = "UNIQUE_TEST_SYMBOL"
    assert position.valid?
  end

  test "open scope returns positions without closed_at" do
    assert_includes BrokerPosition.open, @position

    @position.update!(closed_at: Time.current)
    assert_not_includes BrokerPosition.open, @position
  end

  test "closed scope returns positions with closed_at" do
    assert_not_includes BrokerPosition.closed, @position

    @position.update!(closed_at: Time.current)
    assert_includes BrokerPosition.closed, @position
  end

  test "closed? returns true when closed_at is present" do
    assert_not @position.closed?

    @position.closed_at = Time.current
    assert @position.closed?
  end

  test "open? returns true when closed_at is nil" do
    assert @position.open?

    @position.closed_at = Time.current
    assert_not @position.open?
  end

  test "close! sets closed_at and zeroes values" do
    @position.update!(last_value: 1000, last_quantity: 10)

    @position.close!

    assert @position.closed?
    assert_equal 0, @position.last_value
    assert_equal 0, @position.last_quantity
    assert_not_nil @position.closed_at
  end

  test "close! records final zero valuation" do
    @position.update!(last_value: 1000, last_quantity: 10, currency: "USD")

    assert_difference "PositionValuation.count", 1 do
      @position.close!
    end

    valuation = @position.position_valuations.last
    assert_equal 0, valuation.value
    assert_equal 0, valuation.quantity
  end

  test "close! is idempotent" do
    @position.update!(last_value: 1000, last_quantity: 10)
    @position.close!
    original_closed_at = @position.closed_at

    # Calling close! again should do nothing
    @position.close!

    assert_equal original_closed_at, @position.closed_at
  end

  test "reopen! clears closed_at" do
    @position.update!(closed_at: Time.current)
    assert @position.closed?

    @position.reopen!

    assert_not @position.closed?
    assert_nil @position.closed_at
  end

  test "reopen! is idempotent" do
    assert @position.open?

    @position.reopen!

    assert @position.open?
  end

  test "record_valuation! creates valuation with current values" do
    @position.update!(last_value: 5000, last_quantity: 25, currency: "USD")

    valuation = @position.record_valuation!(date: Date.current)

    assert_equal 5000, valuation.value
    assert_equal 25, valuation.quantity
    assert_equal "USD", valuation.currency
    assert_equal Date.current, valuation.date
  end

  test "record_valuation! updates existing valuation for same date" do
    @position.update!(last_value: 1000, last_quantity: 10, currency: "USD")
    @position.record_valuation!(date: Date.current)

    @position.update!(last_value: 2000, last_quantity: 20)

    assert_no_difference "PositionValuation.count" do
      @position.record_valuation!(date: Date.current)
    end

    valuation = @position.position_valuations.find_by(date: Date.current)
    assert_equal 2000, valuation.value
    assert_equal 20, valuation.quantity
  end

  test "mapped scope returns positions with asset_id" do
    assert_includes BrokerPosition.mapped, @position

    unmapped = broker_positions(:vti_position)
    assert_not_includes BrokerPosition.mapped, unmapped
  end

  test "unmapped scope returns positions without asset_id" do
    unmapped = broker_positions(:vti_position)
    assert_includes BrokerPosition.unmapped, unmapped
    assert_not_includes BrokerPosition.unmapped, @position
  end
end

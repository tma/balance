require "test_helper"

class ExpenseProfileDetectionServiceTest < ActiveSupport::TestCase
  setup do
    WebMock.disable_net_connect!
    ExpenseProfile.delete_all
    @account = accounts(:checking_account)
    stub_request(:get, "#{Rails.application.config.ollama.host}/api/tags")
      .to_return(status: 200, body: { models: [] }.to_json, headers: { "Content-Type" => "application/json" })
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "detects a monthly grouped stream without Ollama" do
    category = Category.create!(
      name: "Household utilities",
      category_type: "expense",
      essentiality: "essential"
    )
    CategoryPattern.create!(category: category, pattern: "Electric Co", source: "human")
    [ "2026-05-01", "2026-06-01", "2026-07-01", "2026-08-01" ].each do |date|
      create_expense(category:, description: "ELECTRIC CO BILL", date:, amount: 100)
    end

    ExpenseProfileDetectionService.new(as_of: Date.new(2026, 9, 3)).call

    profile = ExpenseProfile.find_by!(category:, merchant_pattern: "Electric Co")
    assert_equal "monthly", profile.detected_cadence
    assert_equal "high", profile.recurrence_confidence
    assert_equal "essential", profile.essentiality
    assert profile.status_suggested?
    assert_equal 4, profile.occurrence_count
  end

  test "surfaces a material single annual candidate from exact description" do
    category = Category.create!(
      name: "Mixed insurance",
      category_type: "expense",
      essentiality: "mixed"
    )
    create_expense(
      category:,
      description: "ACME ANNUAL HOME POLICY",
      date: "2026-02-10",
      amount: 1200
    )

    ExpenseProfileDetectionService.new(as_of: Date.new(2026, 9, 3)).call

    profile = ExpenseProfile.find_by!(category:, merchant_pattern: "ACME ANNUAL HOME POLICY")
    assert_nil profile.detected_cadence
    assert_includes profile.review_flags, "material"
    assert_includes ExpenseProfile.review_queue, profile
  end

  test "uses longest pattern for recurrence evidence" do
    category = Category.create!(
      name: "Overlapping subscriptions",
      category_type: "expense",
      essentiality: "mixed"
    )
    CategoryPattern.create!(category:, pattern: "Amazon", source: "human")
    CategoryPattern.create!(category:, pattern: "Amazon Prime", source: "human")
    [ "2026-05-01", "2026-06-01", "2026-07-01", "2026-08-01" ].each do |date|
      create_expense(category:, description: "AMAZON PRIME", date:, amount: 15)
    end

    ExpenseProfileDetectionService.new(as_of: Date.new(2026, 9, 3)).call

    assert_equal 4, ExpenseProfile.find_by!(merchant_pattern: "Amazon Prime").occurrence_count
    assert_nil ExpenseProfile.find_by(merchant_pattern: "Amazon")
  end

  test "aggregates split charges by billing date before recurrence analysis" do
    category = Category.create!(name: "Split utility", category_type: "expense", essentiality: "essential")
    CategoryPattern.create!(category: category, pattern: "Power Co", source: "human")
    [ "2026-07-05", "2026-08-05" ].each do |date|
      create_expense(category:, description: "POWER CO SUPPLY", date:, amount: 300)
      create_expense(category:, description: "POWER CO DELIVERY", date:, amount: 100)
    end

    ExpenseProfileDetectionService.new(as_of: Date.new(2026, 9, 3)).call

    profile = ExpenseProfile.find_by!(category:, merchant_pattern: "Power Co")
    assert_equal 2, profile.occurrence_count
    assert_equal 400.to_d, profile.median_amount
    assert_equal "low", profile.recurrence_confidence
    assert_nil profile.detected_cadence
  end

  test "dismissed profile pattern prevents fragmented suggestions after source pattern removal" do
    category = Category.create!(name: "Dismissed grouping", category_type: "expense", essentiality: "mixed")
    pattern = CategoryPattern.create!(category: category, pattern: "Coop", source: "human")
    profile = ExpenseProfile.create!(
      category: category,
      merchant_pattern: "Coop",
      essentiality: "discretionary",
      source: "machine",
      status: "dismissed"
    )
    [ "2026-06-01", "2026-07-01", "2026-08-01" ].each_with_index do |date, index|
      create_expense(category:, description: "COOP ZURICH #{index}", date:, amount: 50)
    end
    pattern.destroy!

    ExpenseProfileDetectionService.new(as_of: Date.new(2026, 9, 3)).call

    assert_equal [ profile ], ExpenseProfile.where(category: category).to_a
    assert_empty ExpenseProfile.review_queue.where(category: category)
  end

  test "invalid Ollama response leaves suggestion unclassified" do
    category = Category.create!(name: "Mixed monthly", category_type: "expense", essentiality: "mixed")
    CategoryPattern.create!(category:, pattern: "Mystery Bill", source: "human")
    [ "2026-05-01", "2026-06-01", "2026-07-01", "2026-08-01" ].each do |date|
      create_expense(category:, description: "MYSTERY BILL", date:, amount: 40)
    end
    host = Rails.application.config.ollama.host
    stub_request(:get, "#{host}/api/tags")
      .to_return(
        status: 200,
        body: { models: [ { name: Rails.application.config.ollama.model } ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    stub_request(:post, "#{host}/api/generate")
      .to_return(
        status: 200,
        body: { response: { wrong: [] }.to_json }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    ExpenseProfileDetectionService.new(as_of: Date.new(2026, 9, 3)).call

    assert_nil ExpenseProfile.find_by!(category:, merchant_pattern: "Mystery Bill").essentiality
  end

  test "classification prompt includes every aggregate candidate" do
    candidates = [
      {
        candidate_id: "profile-1",
        merchant: "Electric Co",
        category: "Utilities",
        occurrence_count: 4,
        first_seen_on: "2026-05-01",
        last_seen_on: "2026-08-01",
        amount_range: 100,
        recurrence: "monthly"
      }
    ]

    prompt = ExpenseProfileDetectionService.classification_prompt(candidates)

    assert_includes prompt, JSON.generate(candidates)
    assert_includes prompt, "Return every candidate exactly once"
    assert_includes prompt, '"essentiality":"essential"'
    assert_includes prompt, "movement of money rather than consumption"
    assert_includes prompt, 'occurrence_count == 1 ? "non_recurring" : "unknown"'
    assert_includes prompt, "Output suggestion count must also be 1"

    schema = ExpenseProfileDetectionService.classification_schema([ "profile-1" ])
    item_schema = schema.dig(:properties, :suggestions, :items)
    assert_equal [ "profile-1" ], item_schema.dig(:properties, :candidate_id, :enum)
    assert_equal ExpenseProfile::ESSENTIALITIES, item_schema.dig(:properties, :essentiality, :enum)
  end

  private

  def create_expense(category:, description:, date:, amount:)
    Transaction.create!(
      account: @account,
      category: category,
      amount: amount,
      transaction_type: "expense",
      date: Date.parse(date),
      description: description
    )
  end
end

require "test_helper"

class CategoryPatternExtractionJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    WebMock.disable_net_connect!
    @ollama_host = Rails.application.config.ollama.host
    @groceries = categories(:groceries)
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "extracts merchant names and creates machine patterns" do
    # Create multiple transactions with same merchant to meet threshold
    3.times do
      Transaction.create!(
        account: accounts(:checking_account),
        category: @groceries,
        amount: 50.0,
        transaction_type: "expense",
        date: Date.current,
        description: "SAFEWAY STORE #1234"
      )
    end

    stub_ollama_available
    stub_request(:post, "#{@ollama_host}/api/generate")
      .to_return(status: 200, body: {
        response: '["SAFEWAY", "SAFEWAY", "SAFEWAY"]'
      }.to_json, headers: { "Content-Type" => "application/json" })

    CategoryPatternExtractionJob.perform_now

    pattern = CategoryPattern.machine.find_by(pattern: "SAFEWAY")
    assert_not_nil pattern, "Should create a machine pattern for SAFEWAY"
    assert_equal @groceries.id, pattern.category_id
  end

  test "respects minimum occurrence threshold" do
    # Create only 1 transaction — below threshold of 2
    Transaction.create!(
      account: accounts(:checking_account),
      category: @groceries,
      amount: 50.0,
      transaction_type: "expense",
      date: Date.current,
      description: "RARE STORE ONCE"
    )

    stub_ollama_available
    stub_request(:post, "#{@ollama_host}/api/generate")
      .to_return(status: 200, body: {
        response: '["RARE STORE"]'
      }.to_json, headers: { "Content-Type" => "application/json" })

    CategoryPatternExtractionJob.perform_now

    pattern = CategoryPattern.machine.find_by(pattern: "RARE STORE")
    assert_nil pattern, "Should not create pattern for merchants below threshold"
  end

  test "full_rebuild deletes existing machine patterns first" do
    assert CategoryPattern.machine.exists?

    stub_ollama_available
    stub_request(:post, "#{@ollama_host}/api/generate")
      .to_return(status: 200, body: { response: "[]" }.to_json,
                 headers: { "Content-Type" => "application/json" })

    CategoryPatternExtractionJob.perform_now(full_rebuild: true)

    assert_equal 0, CategoryPattern.machine.count
  end

  test "scoped rebuild only clears patterns for specified category" do
    other_category = categories(:entertainment)
    CategoryPattern.create!(
      category: other_category,
      pattern: "AMC",
      source: "machine",
      confidence: 0.8
    )

    stub_ollama_available
    stub_request(:post, "#{@ollama_host}/api/generate")
      .to_return(status: 200, body: { response: "[]" }.to_json,
                 headers: { "Content-Type" => "application/json" })

    CategoryPatternExtractionJob.perform_now(category_id: @groceries.id)

    # Entertainment machine patterns should be untouched
    assert CategoryPattern.machine.where(category: other_category).exists?
  end

  test "backfills missing transaction embeddings" do
    txn = transactions(:grocery_shopping)
    txn.update_column(:embedding, nil)

    stub_ollama_available
    stub_request(:post, "#{@ollama_host}/api/generate")
      .to_return(status: 200, body: { response: "[]" }.to_json,
                 headers: { "Content-Type" => "application/json" })

    assert_enqueued_with(job: TransactionEmbeddingJob, args: [ txn.id ]) do
      CategoryPatternExtractionJob.perform_now
    end
  end

  test "handles LLM extraction failure gracefully" do
    Transaction.create!(
      account: accounts(:checking_account),
      category: @groceries,
      amount: 50.0,
      transaction_type: "expense",
      date: Date.current,
      description: "SOME STORE"
    )

    stub_ollama_available
    stub_request(:post, "#{@ollama_host}/api/generate")
      .to_return(status: 500, body: "Internal Server Error")

    assert_nothing_raised do
      CategoryPatternExtractionJob.perform_now
    end
  end

  private

  def stub_ollama_available
    stub_request(:get, "#{@ollama_host}/api/tags")
      .to_return(status: 200, body: { models: [ { name: "#{Rails.application.config.ollama.embedding_model}:latest" } ] }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end
end

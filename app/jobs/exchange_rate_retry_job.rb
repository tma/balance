# Retries exchange rate fetches for records that failed previously
# Runs hourly via Solid Queue recurring schedule
class ExchangeRateRetryJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "[ExchangeRateRetryJob] Starting exchange rate retry"

    counts = {
      transactions: retry_transactions,
      accounts: retry_accounts,
      assets: retry_assets,
      asset_valuations: retry_asset_valuations,
      position_valuations: retry_position_valuations
    }

    total = counts.values.sum
    if total > 0
      Rails.logger.info "[ExchangeRateRetryJob] Retried #{total} records: #{counts.inspect}"
    else
      Rails.logger.info "[ExchangeRateRetryJob] No records needed exchange rate retry"
    end
  end

  private

  def retry_transactions
    count = 0
    Transaction.needs_exchange_rate.find_each do |record|
      record.save
      count += 1 if record.exchange_rate.present?
    end
    count
  end

  def retry_accounts
    count = 0
    Account.needs_exchange_rate.find_each do |record|
      record.save
      count += 1 if record.exchange_rate.present?
    end
    count
  end

  def retry_assets
    count = 0
    Asset.unscoped.needs_exchange_rate.find_each do |record|
      record.save
      count += 1 if record.exchange_rate.present?
    end
    count
  end

  def retry_asset_valuations
    count = 0
    AssetValuation.unscoped.needs_exchange_rate.find_each do |record|
      record.save
      count += 1 if record.exchange_rate.present?
    end
    count
  end

  def retry_position_valuations
    count = 0
    PositionValuation.needs_exchange_rate.find_each do |record|
      record.save
      count += 1 if record.exchange_rate.present?
    end
    count
  end
end

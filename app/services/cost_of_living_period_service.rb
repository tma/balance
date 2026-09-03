class CostOfLivingPeriodService
  AMOUNT_MONTHS = 12

  attr_reader :as_of, :data_complete_through

  def initialize(as_of: Date.current, data_complete_through: nil)
    @as_of = as_of
    @data_complete_through = data_complete_through&.beginning_of_month
  end

  def call
    automatic_month, limiting_accounts = automatic_data_complete_through
    effective_month = data_complete_through || automatic_month

    {
      automatic_data_complete_through: automatic_month,
      data_complete_through: effective_month,
      data_complete_through_source: data_complete_through ? "manual" : "automatic",
      window_start: effective_month - (AMOUNT_MONTHS - 1).months,
      window_end: effective_month.end_of_month,
      limiting_accounts: limiting_accounts,
      available_months: available_months
    }
  end

  private

  def automatic_data_complete_through
    latest_completed_month = as_of.prev_month.beginning_of_month
    tracked_accounts = Account.active.where.not(expected_transaction_frequency: nil).to_a
    last_dates = Transaction.where(account_id: tracked_accounts.map(&:id))
      .group(:account_id)
      .maximum(:date)

    account_months = tracked_accounts.filter_map do |account|
      last_date = last_dates[account.id]
      next unless last_date

      supported_through = last_date + account.expected_transaction_frequency.days
      [ account, completed_month_supported_by(supported_through, latest_completed_month) ]
    end
    return [ latest_completed_month, [] ] if account_months.empty?

    automatic_month = account_months.map(&:last).min
    limiting_accounts = account_months.filter_map do |account, month|
      account if month == automatic_month && automatic_month < latest_completed_month
    end
    [ automatic_month, limiting_accounts ]
  end

  def completed_month_supported_by(supported_through, latest_completed_month)
    supported_month = if supported_through == supported_through.end_of_month
      supported_through.beginning_of_month
    else
      supported_through.prev_month.beginning_of_month
    end

    [ supported_month, latest_completed_month ].min
  end

  def available_months
    latest = as_of.prev_month.beginning_of_month
    earliest = Transaction.minimum(:date)&.beginning_of_month || latest
    month_count = (latest.year * 12 + latest.month) - (earliest.year * 12 + earliest.month)

    month_count.downto(0).map { |offset| earliest + offset.months }
  end
end

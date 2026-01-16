require "digest"

class DuplicateDetectionService
  class << self
    # Generate a hash for duplicate detection
    # @param date [Date, String] Transaction date
    # @param amount [Numeric, String] Transaction amount
    # @param description [String] Transaction description
    # @return [String] SHA256 hash
    def hash_for(date, amount, description)
      normalized_date = date.is_a?(Date) ? date.iso8601 : date.to_s
      normalized_amount = amount.to_f.round(2).to_s
      normalized_description = description.to_s.downcase.strip.gsub(/\s+/, " ")

      Digest::SHA256.hexdigest("#{normalized_date}|#{normalized_amount}|#{normalized_description}")
    end

    # Find which transaction hashes already exist in the database
    # @param hashes [Array<String>] Array of duplicate hashes to check
    # @return [Set<String>] Set of hashes that already exist
    def find_existing_hashes(hashes)
      return Set.new if hashes.empty?

      existing = Transaction.where(duplicate_hash: hashes).pluck(:duplicate_hash)
      Set.new(existing)
    end

    # Check if a specific transaction already exists
    # @param date [Date, String] Transaction date
    # @param amount [Numeric, String] Transaction amount
    # @param description [String] Transaction description
    # @return [Boolean]
    def duplicate?(date, amount, description)
      hash = hash_for(date, amount, description)
      Transaction.exists?(duplicate_hash: hash)
    end

    # Mark transactions as duplicates in a list of transaction hashes
    # @param transactions [Array<Hash>] Array of transaction hashes with :date, :amount, :description
    # @return [Array<Hash>] Same array with :duplicate_hash and :is_duplicate added
    def mark_duplicates(transactions)
      # Generate hashes for all transactions
      transactions.each do |txn|
        txn[:duplicate_hash] = hash_for(txn[:date], txn[:amount], txn[:description])
      end

      # Find which ones already exist
      hashes = transactions.map { |t| t[:duplicate_hash] }
      existing = find_existing_hashes(hashes)

      # Mark duplicates
      transactions.each do |txn|
        txn[:is_duplicate] = existing.include?(txn[:duplicate_hash])
      end

      transactions
    end
  end
end

namespace :categorization do
  desc "Bootstrap categorization from existing transaction history"
  task bootstrap: :environment do
    unless OllamaService.available?
      puts "Error: Ollama is not available"
      exit 1
    end

    puts "Enqueuing full rebuild (embeddings + patterns)..."
    puts "The hourly CategoryPatternExtractionJob handles this automatically,"
    puts "but this triggers it immediately with a full rebuild."

    # Step 1: Embed all transactions without embeddings
    transactions = Transaction.where(embedding: nil)
    puts "Enqueuing embedding for #{transactions.count} transactions..."
    transactions.find_each do |txn|
      TransactionEmbeddingJob.perform_later(txn.id)
    end

    # Step 2: Extract patterns (full rebuild)
    puts "Enqueuing pattern extraction (full rebuild)..."
    CategoryPatternExtractionJob.perform_later(full_rebuild: true)

    puts "Jobs enqueued. Monitor with: rails solid_queue:monitor"
  end

  desc "Re-embed everything after changing the embedding model"
  task migrate_embeddings: :environment do
    unless OllamaService.available?
      puts "Error: Ollama is not available"
      exit 1
    end

    puts "This will clear ALL embeddings and machine patterns, then rebuild."
    puts "Embedding jobs will be enqueued in the background."
    EmbeddingModelMigrationJob.perform_later
    puts "EmbeddingModelMigrationJob enqueued. Monitor with: rails solid_queue:monitor"
  end

  desc "Benchmark categorization accuracy with synthetic data (requires Ollama)"
  task benchmark: :environment do
    unless OllamaService.available?
      puts "Error: Ollama is not available. Benchmark requires real model calls."
      exit 1
    end

    require_relative "../../lib/categorization_benchmark"

    benchmark = CategorizationBenchmark.new
    results = benchmark.run
    benchmark.report(results)

    exit(results[:all_passed] ? 0 : 1)
  end
end

namespace :categories do
  desc "Recompute category and transaction embeddings with the configured model"
  task compute_embeddings: :environment do
    unless LlmService.available?
      puts "Error: LLM server is not available at #{Rails.application.config.ollama.host}"
      exit 1
    end

    unless LlmService.embedding_model_available?
      model = Rails.application.config.ollama.embedding_model
      puts "Error: Embedding model '#{model}' is not available"
      exit 1
    end

    Category.update_all(embedding: nil)
    Transaction.update_all(embedding: nil)

    success_count = 0
    error_count = 0

    categories = Category.all
    puts "Computing embeddings for #{categories.count} categories..."
    categories.each do |category|
      print "  #{category.name} (#{category.category_type})... "
      vector = LlmService.embed(category.embedding_text)
      category.update_column(:embedding, vector.pack("f*"))
      puts "done (#{vector.size} dimensions)"
      success_count += 1
    rescue LlmService::Error => e
      puts "FAILED: #{e.message}"
      error_count += 1
    end

    transactions = Transaction.where.not(description: [ nil, "" ])
    puts "Computing embeddings for #{transactions.count} transactions..."
    transactions.find_each do |transaction|
      vector = LlmService.embed(transaction.description)
      transaction.update_column(:embedding, vector.pack("f*"))
      success_count += 1
    rescue LlmService::Error => e
      puts "  FAILED transaction #{transaction.id}: #{e.message}"
      error_count += 1
    end

    puts "Completed: #{success_count} successful, #{error_count} failed"
    exit 1 if error_count > 0
  end

  desc "Clear category and transaction embeddings"
  task clear_embeddings: :environment do
    category_count = Category.where.not(embedding: nil).count
    transaction_count = Transaction.where.not(embedding: nil).count
    Category.update_all(embedding: nil)
    Transaction.update_all(embedding: nil)
    puts "Cleared embeddings from #{category_count} categories and #{transaction_count} transactions"
  end

  desc "Show embedding status for all categories"
  task embedding_status: :environment do
    categories = Category.all.order(:category_type, :name)

    puts "Category Embedding Status"
    puts "=" * 60
    puts

    %w[expense income].each do |type|
      type_categories = categories.select { |c| c.category_type == type }
      with_embedding = type_categories.count { |c| c.embedding.present? }

      puts "#{type.upcase} (#{with_embedding}/#{type_categories.count} have embeddings):"

      type_categories.each do |category|
        status = category.embedding.present? ? "+" : "-"
        dims = category.embedding.present? ? "(#{category.embedding_vector.size}d)" : ""
        puts "  [#{status}] #{category.name} #{dims}"
      end

      puts
    end
  end
end

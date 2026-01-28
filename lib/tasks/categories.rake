namespace :categories do
  desc "Compute embeddings for all categories (requires Ollama with nomic-embed-text model)"
  task compute_embeddings: :environment do
    unless OllamaService.available?
      puts "Error: Ollama is not available at #{Rails.application.config.ollama.host}"
      puts "Please ensure Ollama is running and try again."
      exit 1
    end

    unless OllamaService.embedding_model_available?
      model = Rails.application.config.ollama.embedding_model
      puts "Error: Embedding model '#{model}' is not available"
      puts "Please run: ollama pull #{model}"
      exit 1
    end

    categories = Category.all
    puts "Computing embeddings for #{categories.count} categories..."
    puts

    success_count = 0
    error_count = 0

    categories.each do |category|
      print "  #{category.name} (#{category.category_type})... "

      begin
        vector = OllamaService.embed(category.embedding_text)
        category.update_column(:embedding, vector.pack("f*"))
        puts "done (#{vector.size} dimensions)"
        success_count += 1
      rescue OllamaService::Error => e
        puts "FAILED: #{e.message}"
        error_count += 1
      end
    end

    puts
    puts "Completed: #{success_count} successful, #{error_count} failed"

    exit 1 if error_count > 0
  end

  desc "Clear all category embeddings"
  task clear_embeddings: :environment do
    count = Category.where.not(embedding: nil).count
    Category.update_all(embedding: nil)
    puts "Cleared embeddings from #{count} categories"
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

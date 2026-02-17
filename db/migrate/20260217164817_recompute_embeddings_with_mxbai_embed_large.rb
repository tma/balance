class RecomputeEmbeddingsWithMxbaiEmbedLarge < ActiveRecord::Migration[8.1]
  def up
    # Clear all existing embeddings (they were generated with nomic-embed-text at 768 dimensions,
    # but we've switched to mxbai-embed-large at 1024 dimensions)
    execute "UPDATE categories SET embedding = NULL"
    execute "UPDATE transactions SET embedding = NULL"

    # Attempt to recompute category embeddings immediately
    recompute_category_embeddings
  end

  def down
    # Cannot restore old embeddings — they must be recomputed regardless
    say "Embeddings must be recomputed manually after rollback."
  end

  private

  def recompute_category_embeddings
    unless OllamaService.available? && OllamaService.embedding_model_available?
      say "Ollama not available — skipping embedding recomputation."
      say "Run `rails categories:compute_embeddings` when Ollama is ready."
      return
    end

    categories = Category.all
    say "Recomputing embeddings for #{categories.count} categories with mxbai-embed-large..."

    success = 0
    categories.each do |category|
      vector = OllamaService.embed(category.embedding_text)
      category.update_column(:embedding, vector.pack("f*"))
      success += 1
    rescue StandardError => e
      say "  Failed for '#{category.name}': #{e.message}"
    end

    say "Recomputed #{success}/#{categories.count} category embeddings."
  end
end

class Admin::CategoryPatternsController < ApplicationController
  before_action :set_category

  def create
    pattern_text = params[:pattern].to_s.strip
    if pattern_text.present?
      @category.category_patterns.find_or_create_by!(pattern: pattern_text, source: "human")
      redirect_to edit_admin_category_path(@category), notice: "Pattern added.", status: :see_other
    else
      redirect_to edit_admin_category_path(@category), alert: "Pattern cannot be blank.", status: :see_other
    end
  end

  def destroy
    pattern = @category.category_patterns.find(params[:id])
    pattern.destroy!
    redirect_to edit_admin_category_path(@category), notice: "Pattern removed.", status: :see_other
  end

  def regenerate
    @category.category_patterns.machine.delete_all
    PatternExtractionJob.perform_later(category_id: @category.id, full_rebuild: true)
    redirect_to edit_admin_category_path(@category), notice: "Learned patterns cleared. Regeneration queued.", status: :see_other
  end

  private

  def set_category
    @category = Category.find(params[:category_id])
  end
end

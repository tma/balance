class Admin::CategoriesController < ApplicationController
  before_action :set_category, only: %i[ show edit update destroy ]

  def index
    @categories = Category.left_joins(:category_patterns)
                         .select("categories.*",
                                 "COUNT(CASE WHEN category_patterns.source = 'human' THEN 1 END) AS human_patterns_count",
                                 "COUNT(CASE WHEN category_patterns.source = 'machine' THEN 1 END) AS machine_patterns_count")
                         .group("categories.id")
                         .order(:category_type, :name)
  end

  def show
  end

  def new
    @category = Category.new
  end

  def edit
  end

  def create
    @category = Category.new(category_params)

    if @category.save
      redirect_to admin_category_path(@category), notice: "Category was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @category.update(category_params)
      redirect_to admin_category_path(@category), notice: "Category was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @category.destroy!
    redirect_to admin_categories_path, notice: "Category was successfully destroyed.", status: :see_other
  end

  def regenerate_all
    CategoryPattern.machine.delete_all
    PatternExtractionJob.perform_later(full_rebuild: true)
    redirect_to admin_categories_path, notice: "All learned patterns cleared. Learning queued.", status: :see_other
  end

  private

  def set_category
    @category = Category.find(params.expect(:id))
  end

  def category_params
    params.expect(category: [ :name, :category_type ])
  end
end

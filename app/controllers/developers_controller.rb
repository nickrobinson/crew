class DevelopersController < ApplicationController
  def index
    @developers = Developer.includes(:contributions).all

    # Filters
    @developers = @developers.by_status(params[:status])
    @developers = @developers.by_location(params[:location]) if params[:location].present?
    @developers = @developers.with_email if params[:has_email] == "1"

    # Sorting
    case params[:sort]
    when "followers"
      @developers = @developers.order(followers_count: :desc)
    when "recent"
      @developers = @developers.order(created_at: :desc)
    else
      # Sort by total contributions (default)
      @developers = @developers.left_joins(:contributions)
                               .group(:id)
                               .order("SUM(contributions.contributions_count) DESC NULLS LAST")
    end

    @developers = @developers.limit(100)
  end

  def show
    @developer = Developer.find(params[:id])
    @contributions = @developer.contributions.includes(:repository).order(contributions_count: :desc)
  end

  def update
    @developer = Developer.find(params[:id])

    if @developer.update(developer_params)
      respond_to do |format|
        format.html { redirect_to @developer, notice: "Developer updated" }
        format.turbo_stream
      end
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def developer_params
    params.require(:developer).permit(:status, :notes)
  end
end

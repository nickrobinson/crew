class DevelopersController < ApplicationController
  before_action :set_project
  before_action :set_developer, only: [:show, :update]

  def index
    @project_developers = filtered_project_developers.limit(100)
  end

  def export
    project_developers = filtered_project_developers

    csv_data = CSV.generate(headers: true) do |csv|
      csv << ["Name", "Username", "Email", "Location", "Company", "Followers", "Contributions", "Status", "GitHub URL", "Notes"]

      project_developers.each do |pd|
        dev = pd.developer
        csv << [
          dev.name,
          dev.github_username,
          dev.email,
          dev.location,
          dev.company,
          dev.followers_count,
          pd.total_contributions_count.to_i,
          pd.status,
          dev.profile_url,
          pd.notes
        ]
      end
    end

    send_data csv_data,
              filename: "#{@project.name.parameterize}-developers-#{Date.current}.csv",
              type: "text/csv"
  end

  def show
    @project_developer = @project.project_developers.find_by!(developer: @developer)
    @contributions = @developer.contributions
                               .includes(:repository)
                               .where(repository: @project.repositories)
                               .order(contributions_count: :desc)
  end

  def update
    @project_developer = @project.project_developers.find_by!(developer: @developer)

    if @project_developer.update(project_developer_params)
      respond_to do |format|
        format.html { redirect_to project_developer_path(@project, @developer), notice: "Developer updated" }
        format.turbo_stream
      end
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_developer
    @developer = Developer.find(params[:id])
  end

  def filtered_project_developers
    # Get project developers with contribution counts for this project's repos
    repo_ids = @project.repository_ids

    project_developers = @project.project_developers
                                  .joins(:developer)
                                  .left_joins(developer: :contributions)
                                  .where(contributions: { repository_id: repo_ids })
                                  .or(@project.project_developers
                                       .joins(:developer)
                                       .left_joins(developer: :contributions)
                                       .where(contributions: { id: nil }))
                                  .select("project_developers.*, developers.*, COALESCE(SUM(contributions.contributions_count), 0) AS total_contributions_count")
                                  .group("project_developers.id, developers.id")

    # Filters
    project_developers = project_developers.where(status: params[:status]) if params[:status].present?
    project_developers = project_developers.where("developers.location LIKE ?", "%#{params[:location]}%") if params[:location].present?
    project_developers = project_developers.where.not(developers: { email: [nil, ""] }) if params[:has_email] == "1"

    # Sorting
    case params[:sort]
    when "followers"
      project_developers.order("developers.followers_count DESC")
    when "recent"
      project_developers.order("project_developers.created_at DESC")
    else
      project_developers.order(Arel.sql("total_contributions_count DESC"))
    end
  end

  def project_developer_params
    params.require(:project_developer).permit(:status, :notes)
  end
end

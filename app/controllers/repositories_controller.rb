class RepositoriesController < ApplicationController
  before_action :set_project

  def index
    @repositories = @project.repositories.order(created_at: :desc)
  end

  def show
    @repository = @project.repositories.find(params[:id])
    @contributions = @repository.contributions
                                .includes(:developer)
                                .order(contributions_count: :desc)

    if params[:status].present?
      developer_ids = @project.project_developers.where(status: params[:status]).pluck(:developer_id)
      @contributions = @contributions.where(developer_id: developer_ids)
    end
  end

  def create
    url = params[:github_url].to_s.strip

    # Parse GitHub URL
    match = url.match(%r{github\.com/([^/]+)/([^/]+)})
    unless match
      redirect_to project_repositories_path(@project), alert: "Invalid GitHub URL"
      return
    end

    name = "#{match[1]}/#{match[2]}"

    @repository = @project.repositories.find_or_initialize_by(github_url: url)
    if @repository.new_record?
      @repository.name = name
      @repository.save!
      ImportRepositoryJob.perform_later(@repository.id)
      redirect_to project_repository_path(@project, @repository), notice: "Import started for #{name}"
    else
      redirect_to project_repository_path(@project, @repository), notice: "Repository already exists"
    end
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end
end

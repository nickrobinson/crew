class RepositoriesController < ApplicationController
  def index
    @repositories = Repository.order(created_at: :desc)
  end

  def show
    @repository = Repository.find(params[:id])
    @contributions = @repository.contributions
                                .includes(:developer)
                                .order(contributions_count: :desc)

    if params[:status].present?
      @contributions = @contributions.joins(:developer).where(developers: { status: params[:status] })
    end
  end

  def create
    url = params[:github_url].to_s.strip

    # Parse GitHub URL
    match = url.match(%r{github\.com/([^/]+)/([^/]+)})
    unless match
      redirect_to repositories_path, alert: "Invalid GitHub URL"
      return
    end

    name = "#{match[1]}/#{match[2]}"

    @repository = Repository.find_or_initialize_by(github_url: url)
    if @repository.new_record?
      @repository.name = name
      @repository.save!
      ImportRepositoryJob.perform_later(@repository.id)
      redirect_to @repository, notice: "Import started for #{name}"
    else
      redirect_to @repository, notice: "Repository already exists"
    end
  end
end

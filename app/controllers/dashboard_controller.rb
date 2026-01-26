class DashboardController < ApplicationController
  def index
    @total_developers = Developer.count
    @developers_by_status = Developer.group(:status).count
    @total_repositories = Repository.count
    @recent_imports = Repository.order(created_at: :desc).limit(5)
  end
end

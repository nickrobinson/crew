class ProjectsController < ApplicationController
  before_action :set_project, only: [:show, :edit, :update, :destroy]

  def index
    @projects = Project.all.order(created_at: :desc)
  end

  def show
    @recent_imports = @project.repositories.order(created_at: :desc).limit(5)
    @developer_stats = {
      total: @project.project_developers.count,
      new: @project.project_developers.where(status: "new").count,
      interesting: @project.project_developers.where(status: "interesting").count,
      contacted: @project.project_developers.where(status: "contacted").count,
      not_a_fit: @project.project_developers.where(status: "not_a_fit").count
    }
  end

  def new
    @project = Project.new
  end

  def create
    @project = Project.new(project_params)

    if @project.save
      redirect_to @project, notice: "Project created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @project.update(project_params)
      redirect_to @project, notice: "Project updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @project.destroy
    redirect_to projects_path, notice: "Project deleted."
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:name, :description)
  end
end

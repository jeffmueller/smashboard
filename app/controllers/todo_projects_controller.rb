# frozen_string_literal: true

class TodoProjectsController < ApplicationController
  before_action :set_project, only: %i[update destroy]

  def index
    @projects = current_user.todo_projects.ordered
    @project = current_user.todo_projects.new
  end

  def create
    @project = current_user.todo_projects.new(project_params)

    if @project.save
      redirect_to todo_projects_path, notice: "Added #{@project.name}."
    else
      @projects = current_user.todo_projects.ordered
      render :index, status: :unprocessable_content
    end
  end

  def update
    if @project.update(project_params)
      redirect_to todo_projects_path, notice: "Updated #{@project.name}."
    else
      @projects = current_user.todo_projects.ordered
      render :index, status: :unprocessable_content
    end
  end

  def destroy
    # Todos outlive their project — nullify rather than cascade, so deleting a
    # project never silently deletes work.
    @project.destroy!
    redirect_to todo_projects_path, notice: "Deleted #{@project.name}."
  end

  private

  def set_project
    @project = current_user.todo_projects.find(params.expect(:id))
  end

  def project_params
    params.expect(todo_project: %i[name color position archived_at])
  end
end

# frozen_string_literal: true

class TodosController < ApplicationController
  before_action :set_todo, only: %i[update destroy complete uncomplete]

  def index
    @todos = current_user.todos.incomplete.ordered.includes(:todo_project)
    @projects = current_user.todo_projects.active.ordered
  end

  def create
    @todo = current_user.todos.new(todo_params)

    if @todo.save
      respond_to do |format|
        format.turbo_stream { render turbo_stream: refreshed_todos_panel }
        format.html { redirect_back_or_to(root_path) }
      end
    else
      head :unprocessable_content
    end
  end

  def update
    if @todo.update(todo_params)
      render turbo_stream: refreshed_todos_panel
    else
      head :unprocessable_content
    end
  end

  def destroy
    @todo.destroy!
    render turbo_stream: refreshed_todos_panel
  end

  def complete
    @todo.complete!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: refreshed_todos_panel }
      format.html { redirect_back_or_to(root_path) }
      format.json { head :no_content }
    end
  end

  def uncomplete
    @todo.uncomplete!
    render turbo_stream: refreshed_todos_panel
  end

  private

  def set_todo
    @todo = current_user.todos.find(params.expect(:id))
  end

  def refreshed_todos_panel
    panel = current_user.panels.find_by(kind: 'todos')
    return turbo_stream.replace('flash', partial: 'shared/flash') if panel.nil?

    turbo_stream.replace(panel.to_stream_target, partial: 'panels/panel', locals: { panel: panel })
  end

  def todo_params
    params.expect(todo: %i[title notes due_at defer_until flagged rrule todo_project_id position])
  end
end

# frozen_string_literal: true

module Api
  module V1
    class TodosController < BaseController
      before_action :set_todo, only: %i[show update destroy complete uncomplete]

      def index
        scope = params[:scope] == 'today' ? Todo.for_today(current_user) : current_user.todos.incomplete
        render json: { todos: scope.ordered.includes(:todo_project).map { |t| TodoSerializer.new(t).as_json } }
      end

      def show
        render json: TodoSerializer.new(@todo).as_json
      end

      def create
        todo = current_user.todos.create!(todo_params)
        render json: TodoSerializer.new(todo).as_json, status: :created
      end

      def update
        @todo.update!(todo_params)
        render json: TodoSerializer.new(@todo).as_json
      end

      def destroy
        @todo.destroy!
        head :no_content
      end

      def complete
        @todo.complete!
        render json: TodoSerializer.new(@todo).as_json
      end

      def uncomplete
        @todo.uncomplete!
        render json: TodoSerializer.new(@todo).as_json
      end

      private

      def set_todo
        @todo = current_user.todos.find(params.expect(:id))
      end

      def todo_params
        params.expect(todo: %i[title notes due_at defer_until flagged rrule todo_project_id position])
      end
    end
  end
end

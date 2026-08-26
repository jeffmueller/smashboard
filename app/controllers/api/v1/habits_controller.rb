# frozen_string_literal: true

module Api
  module V1
    class HabitsController < BaseController
      before_action :set_habit, only: %i[show update destroy toggle archive unarchive]

      def index
        scope = params[:scope] == 'all' ? current_user.habits : current_user.habits.active
        render json: { habits: scope.ordered.map { |habit| serialize(habit) } }
      end

      def show
        render json: serialize(@habit)
      end

      def create
        habit = current_user.habits.new(habit_params)
        habit.position = current_user.habits.next_position
        habit.save!
        render json: serialize(habit), status: :created
      end

      def update
        @habit.update!(habit_params)
        render json: serialize(@habit)
      end

      def destroy
        @habit.destroy!
        head :no_content
      end

      # Optionally for a given day, so a client can fill in yesterday without
      # having to pretend it is yesterday.
      def toggle
        @habit.toggle_completion!(date)
        render json: serialize(@habit)
      end

      # Archiving rather than deleting keeps the completions, so the activity
      # graph doesn't develop holes in its own past. `archived` is on the
      # serializer and `?scope=all` lists them, so a client can round-trip.
      def archive
        @habit.archive!
        render json: serialize(@habit)
      end

      def unarchive
        @habit.unarchive!
        render json: serialize(@habit)
      end

      def reorder
        return head :unprocessable_content unless current_user.habits.apply_order(params[:habit_ids])

        head :no_content
      end

      private

      def set_habit
        @habit = current_user.habits.find(params.expect(:id))
      end

      def serialize(habit)
        HabitSerializer.new(habit, today: today).as_json
      end

      # The user's day, not the server's. Unlike ApplicationController, the API
      # base controller inherits ActionController::API and has no
      # `around_action :use_user_time_zone`, so `Time.zone` here is whatever the
      # process default is — UTC in production. Reading it would mark tomorrow
      # done for anyone west of it who checks in after their evening.
      def today
        current_user.today
      end

      def date
        Date.parse(params[:date].to_s)
      rescue ArgumentError, TypeError
        today
      end

      def habit_params
        params.expect(habit: %i[name icon position])
      end
    end
  end
end

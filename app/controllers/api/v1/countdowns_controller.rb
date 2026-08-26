# frozen_string_literal: true

module Api
  module V1
    class CountdownsController < BaseController
      before_action :set_countdown, only: %i[show update destroy dismiss]

      def index
        render json: { countdowns: current_user.countdowns.ordered.map { |c| CountdownSerializer.new(c).as_json } }
      end

      def show
        render json: CountdownSerializer.new(@countdown).as_json
      end

      def create
        countdown = current_user.countdowns.create!(countdown_params)
        render json: CountdownSerializer.new(countdown).as_json, status: :created
      end

      def update
        @countdown.update!(countdown_params)
        render json: CountdownSerializer.new(@countdown).as_json
      end

      def destroy
        @countdown.destroy!
        head :no_content
      end

      # Body: { "occurrence_at": "2026-08-25T19:15:00Z" }
      def dismiss
        @countdown.dismiss!(Time.iso8601(params.require(:occurrence_at)))
        render json: CountdownSerializer.new(@countdown.reload).as_json
      rescue ArgumentError
        render json: { error: 'occurrence_at must be an ISO 8601 timestamp' }, status: :bad_request
      end

      private

      def set_countdown
        @countdown = current_user.countdowns.find(params.expect(:id))
      end

      def countdown_params
        params.expect(countdown: %i[name description color target_at rrule starts_on occurs_at_time time_zone enabled
                                    position])
      end
    end
  end
end

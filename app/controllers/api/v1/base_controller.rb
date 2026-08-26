# frozen_string_literal: true

module Api
  module V1
    # JSON API root. Authenticates with a bearer ApiToken so native clients
    # never need a session cookie, and falls back to the web session so the PWA
    # can call the same endpoints it already has a login for.
    class BaseController < ActionController::API
      include ActionController::HttpAuthentication::Token::ControllerMethods

      before_action :authenticate_api_user!

      rescue_from ActiveRecord::RecordNotFound, with: :not_found
      rescue_from ActiveRecord::RecordInvalid, with: :unprocessable
      rescue_from ActionController::ParameterMissing, with: :bad_request

      attr_reader :current_user

      private

      def authenticate_api_user!
        token = bearer_token
        api_token = ApiToken.authenticate(token)

        return render_unauthorized if api_token.nil?

        api_token.touch_usage!
        @current_user = api_token.user
      end

      def bearer_token
        authenticate_with_http_token { |token, _options| token } ||
          request.headers['X-Api-Token'].presence
      end

      def render_unauthorized
        render json: { error: 'invalid or missing API token' }, status: :unauthorized
      end

      def not_found
        render json: { error: 'not found' }, status: :not_found
      end

      def unprocessable(exception)
        render json: { error: exception.record.errors.full_messages }, status: :unprocessable_content
      end

      def bad_request(exception)
        render json: { error: exception.message }, status: :bad_request
      end
    end
  end
end

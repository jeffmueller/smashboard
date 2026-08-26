# frozen_string_literal: true

module Oauth
  # Slack's OAuth v2 flow, for a **user** token.
  #
  # The parameter that matters is `user_scope`, not `scope`: `scope` asks for a
  # bot token, and a bot's unread count is not the user's. The resulting token
  # arrives nested under `authed_user`, not at the top level.
  #
  # Unlike Google there is no refresh token — a Slack user token is long-lived
  # unless the app has token rotation switched on.
  class Slack
    class Error < StandardError; end
    class NotConfigured < Error; end

    AUTHORIZE_URL = 'https://slack.com/oauth/v2/authorize'
    ACCESS_URL = 'https://slack.com/api/oauth.v2.access'

    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 15

    Result = Struct.new(:credentials, :label, :external_id, keyword_init: true)

    class << self
      def configured?
        client_id.present? && client_secret.present?
      end

      def client_id
        ENV.fetch('SLACK_CLIENT_ID', nil).presence
      end

      def client_secret
        ENV.fetch('SLACK_CLIENT_SECRET', nil).presence
      end

      def authorize_url(redirect_uri:, state:, scopes:)
        raise NotConfigured, 'SLACK_CLIENT_ID and SLACK_CLIENT_SECRET are not set' unless configured?

        "#{AUTHORIZE_URL}?#{{
          client_id: client_id,
          redirect_uri: redirect_uri,
          user_scope: Array(scopes).join(','),
          state: state
        }.to_query}"
      end

      def exchange(code:, redirect_uri:)
        raise NotConfigured, 'SLACK_CLIENT_ID and SLACK_CLIENT_SECRET are not set' unless configured?

        body = post_access(code: code, redirect_uri: redirect_uri)
        token = body.dig('authed_user', 'access_token').presence
        raise Error, 'Slack returned no user token — check the app requests user scopes' if token.blank?

        # The team id, not the name: two workspaces can share a name, and a
        # workspace can be renamed without becoming a different workspace.
        Result.new(credentials: { 'user_token' => token },
                   label: body.dig('team', 'name').presence,
                   external_id: body.dig('team', 'id').presence)
      end

      private

      def post_access(code:, redirect_uri:)
        response = http.post(ACCESS_URL) do |request|
          request.headers['Content-Type'] = 'application/x-www-form-urlencoded'
          request.body = URI.encode_www_form(
            code: code, client_id: client_id, client_secret: client_secret, redirect_uri: redirect_uri
          )
        end

        body = response.body
        # Slack answers failures with HTTP 200 and ok:false, so the envelope is
        # the only reliable signal here as everywhere else.
        raise Error, "Slack refused the authorization: #{error_from(response)}" unless
          body.is_a?(Hash) && body['ok']

        body
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
        raise Error, "Could not reach Slack: #{e.message}"
      end

      def error_from(response)
        body = response.body

        (body.is_a?(Hash) ? body['error'].presence : nil) || "HTTP #{response.status}"
      end

      def http
        Faraday.new do |f|
          f.response :json, content_type: /\bjson/
          f.options.open_timeout = OPEN_TIMEOUT
          f.options.timeout = READ_TIMEOUT
        end
      end
    end
  end
end

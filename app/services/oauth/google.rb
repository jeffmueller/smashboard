# frozen_string_literal: true

module Oauth
  # The Google authorization-code flow, just enough of it to end up holding a
  # refresh token for one calendar account.
  #
  # Two parameters do all the work and are easy to omit:
  #   access_type=offline — without it Google issues no refresh token at all,
  #                         only an access token that dies in an hour.
  #   prompt=consent      — without it a *second* authorization for an account
  #                         that already granted access returns no refresh token.
  class Google
    class Error < StandardError; end
    class NotConfigured < Error; end

    AUTHORIZE_URL = 'https://accounts.google.com/o/oauth2/v2/auth'
    TOKEN_URL = 'https://oauth2.googleapis.com/token'
    USERINFO_URL = 'https://www.googleapis.com/oauth2/v2/userinfo'

    # Only ever enough identity to label the connection; the useful scope comes
    # from whichever provider is being connected.
    IDENTITY_SCOPE = 'https://www.googleapis.com/auth/userinfo.email'

    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 15

    Result = Struct.new(:credentials, :label, :external_id, keyword_init: true)

    class << self
      def configured?
        client_id.present? && client_secret.present?
      end

      def client_id
        ENV.fetch('GOOGLE_CLIENT_ID', nil).presence
      end

      def client_secret
        ENV.fetch('GOOGLE_CLIENT_SECRET', nil).presence
      end

      def authorize_url(redirect_uri:, state:, scopes:)
        raise NotConfigured, 'GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET are not set' unless configured?

        "#{AUTHORIZE_URL}?#{{
          client_id: client_id,
          redirect_uri: redirect_uri,
          response_type: 'code',
          scope: (Array(scopes) + [IDENTITY_SCOPE]).uniq.join(' '),
          access_type: 'offline',
          prompt: 'consent',
          include_granted_scopes: 'true',
          state: state
        }.to_query}"
      end

      # Trades the one-time code for a refresh token, and asks who it belongs to
      # so the connection can be labelled with the actual account.
      def exchange(code:, redirect_uri:)
        raise NotConfigured, 'GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET are not set' unless configured?

        tokens = post_token(code: code, redirect_uri: redirect_uri)
        refresh_token = tokens['refresh_token'].presence
        raise Error, refusal_message if refresh_token.blank?

        email = email_for(tokens['access_token'])

        Result.new(credentials: { 'refresh_token' => refresh_token },
                   label: email, external_id: email)
      end

      private

      def post_token(code:, redirect_uri:)
        response = http.post(TOKEN_URL) do |request|
          request.headers['Content-Type'] = 'application/x-www-form-urlencoded'
          request.body = URI.encode_www_form(
            code: code, client_id: client_id, client_secret: client_secret,
            redirect_uri: redirect_uri, grant_type: 'authorization_code'
          )
        end

        return response.body if response.status == 200 && response.body.is_a?(Hash)

        raise Error, "Google refused the authorization code: #{error_from(response)}"
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
        raise Error, "Could not reach Google: #{e.message}"
      end

      # Best effort — a connection without a label is a cosmetic problem, not a
      # reason to throw away a token we just successfully obtained.
      def email_for(access_token)
        return nil if access_token.blank?

        response = http.get(USERINFO_URL) { |request| request.headers['Authorization'] = "Bearer #{access_token}" }
        response.status == 200 && response.body.is_a?(Hash) ? response.body['email'].presence : nil
      rescue StandardError
        nil
      end

      def error_from(response)
        body = response.body
        return "HTTP #{response.status}" unless body.is_a?(Hash)

        [body['error'], body['error_description']].compact_blank.join(' — ').presence || "HTTP #{response.status}"
      end

      def refusal_message
        'Google returned no refresh token. That usually means this account has already ' \
          'granted access — revoke smashboard at myaccount.google.com/permissions and try again.'
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

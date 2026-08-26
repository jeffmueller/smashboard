# frozen_string_literal: true

module Integrations
  # Turning a stored refresh token into a usable access token, shared by every
  # Google-backed integration so the invalid_grant handling exists once.
  # Errors are qualified: a bare `AuthenticationError` here would resolve
  # against this module's own lexical scope, not the including class's
  # ancestors, and raise NameError instead.
  module GoogleToken
    TOKEN_URL = 'https://oauth2.googleapis.com/token'

    private

    # Access tokens last an hour; caching one avoids a token round-trip on every
    # refresh. Keyed by connection so two Google accounts never collide.
    def access_token
      cached = Rails.cache.read(token_cache_key)
      return cached if cached.present?

      refresh_access_token
    end

    def refresh_access_token
      response = http(TOKEN_URL).post('') do |request|
        request.headers['Content-Type'] = 'application/x-www-form-urlencoded'
        request.body = URI.encode_www_form(
          grant_type: 'refresh_token', refresh_token: refresh_token,
          client_id: google_client_id, client_secret: google_client_secret
        )
      end

      guard_refresh(response)

      token = response.body['access_token']
      raise Base::AuthenticationError, 'Google returned no access token' if token.blank?

      # Expire a minute early so a token can't lapse mid-request.
      Rails.cache.write(token_cache_key, token, expires_in: (response.body['expires_in'].to_i - 60).clamp(60, 3600))
      token
    end

    # Only `invalid_grant` means the grant is actually dead — revoked, unused for
    # six months, or expired because the consent screen is still in Testing.
    # Anything else is Google having a bad minute, and reporting that as a dead
    # grant would send someone through a pointless re-consent.
    def guard_refresh(response)
      return if response.status == 200

      error = response.body.is_a?(Hash) ? response.body['error'].to_s : ''
      raise Base::AuthenticationError, dead_grant_message(response) if error == 'invalid_grant'

      raise Base::Unavailable, "Google could not refresh the token right now (HTTP #{response.status})"
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      raise Base::Unavailable, "Google was unreachable: #{e.message}"
    end

    def dead_grant_message(response)
      subtype = response.body.is_a?(Hash) ? response.body['error_subtype'].presence : nil

      ['Google access needs granting again', subtype].compact.join(' — ')
    end

    def refresh_token
      credentials['refresh_token'].presence ||
        raise(Base::AuthenticationError, 'no Google refresh token stored for this connection')
    end

    def google_client_id
      ENV['GOOGLE_CLIENT_ID'].presence || raise(Base::Error, 'GOOGLE_CLIENT_ID is not set')
    end

    def google_client_secret
      ENV['GOOGLE_CLIENT_SECRET'].presence || raise(Base::Error, 'GOOGLE_CLIENT_SECRET is not set')
    end

    def token_cache_key
      "google_token/#{connection.id}"
    end
  end
end

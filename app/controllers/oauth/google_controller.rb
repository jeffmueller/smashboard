# frozen_string_literal: true

module Oauth
  # Connect-with-Google, for both Calendar and Gmail. The scopes come from
  # whichever provider is being connected.
  class GoogleController < BaseController
    private

    def oauth_key = :google
    def service = Oauth::Google
    def callback_url = oauth_google_callback_url

    def configuration_message
      'Connecting Google needs GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET set in the environment, ' \
        "and #{oauth_google_callback_url} registered as an authorized redirect URI."
    end
  end
end

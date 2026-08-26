# frozen_string_literal: true

module Oauth
  class SlackController < BaseController
    private

    def oauth_key = :slack
    def service = Oauth::Slack
    def callback_url = oauth_slack_callback_url

    def configuration_message
      'Connecting Slack needs SLACK_CLIENT_ID and SLACK_CLIENT_SECRET set in the environment, ' \
        "and #{oauth_slack_callback_url} added as a redirect URL on the Slack app."
    end
  end
end

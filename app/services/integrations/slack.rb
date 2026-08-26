# frozen_string_literal: true

module Integrations
  # Unread counts for one Slack workspace, using a user token.
  #
  # It has to be a *user* token (`xoxp-…`): unread is a per-person concept, and a
  # bot token would report the bot's unreads. Scopes needed are `channels:read`,
  # `groups:read`, `im:read` and `mpim:read`.
  #
  # Slack has no endpoint that returns unread counts in one call — the tidy one
  # the desktop client uses is undocumented, so this takes the documented route:
  # list the user's conversations, then ask `conversations.info` for each. That
  # is an N+1 by construction, so the fan-out is budgeted (see LOOKUP_BUDGET) and
  # the panel reports how much of the workspace it actually managed to check
  # rather than quietly under-counting.
  class Slack < Base
    DEFAULT_BASE_URL = 'https://slack.com/api/'

    # conversations.info is Tier 3 (50+/minute). At the panel's refresh interval
    # this budget keeps the sustained rate well under that.
    LOOKUP_BUDGET = 40
    PAGE_SIZE = 200
    MAX_PAGES = 5
    NAMED_CONVERSATIONS = 5
    IDENTITY_TTL = 12.hours

    # Slack answers failures with HTTP 200 and `{"ok": false, "error": …}`, so
    # these are matched on the envelope's error string, never on status.
    AUTH_ERRORS = %w[
      invalid_auth not_authed token_revoked token_expired account_inactive
      missing_scope no_permission invalid_token
    ].freeze

    def workspace
      Rails.cache.fetch("slack/workspace/#{connection.id}", expires_in: IDENTITY_TTL) do
        body = call('auth.test')
        { team: body['team'], team_id: body['team_id'], user: body['user'], url: body['url'] }
      end
    end

    def unread(budget: LOOKUP_BUDGET)
      conversations = list_conversations
      # Direct messages first: they are the actionable ones, and there are
      # usually few enough that they all fit inside the budget.
      direct, channels = conversations.partition { |conversation| direct?(conversation) }
      checked = (direct + channels).first(budget)

      tally(checked, conversations.size - checked.size)
    end

    private

    def tally(checked, skipped)
      counted = checked.filter_map { |conversation| counted_conversation(conversation) }
      direct, channels = counted.partition { |entry| entry[:direct] }

      {
        dm_unread: direct.sum { |entry| entry[:unread] },
        channel_unread: channels.sum { |entry| entry[:unread] },
        conversations_checked: checked.size,
        conversations_skipped: skipped,
        top: name_top(counted.select { |entry| entry[:unread].positive? }
                             .sort_by { |entry| -entry[:unread] }
                             .first(NAMED_CONVERSATIONS))
      }
    end

    def counted_conversation(conversation)
      body = call('conversations.info', channel: conversation['id'])
      channel = body['channel'] || {}

      {
        id: conversation['id'],
        direct: direct?(conversation),
        # The *_display count is the one Slack badges with: it leaves out joins,
        # leaves and other noise the user never thinks of as a message.
        unread: channel['unread_count_display'].to_i,
        name: channel['name'].presence,
        user_id: channel['user'].presence
      }
    rescue RateLimited
      # Stop counting rather than fail the whole workspace; the caller already
      # reports how many conversations went unchecked.
      nil
    end

    # Only the handful actually shown get a name resolved, so a workspace with a
    # thousand members doesn't cost a thousand lookups.
    def name_top(entries)
      entries.map do |entry|
        { name: display_name(entry), direct: entry[:direct], unread: entry[:unread] }
      end
    end

    def display_name(entry)
      return "##{entry[:name]}" if entry[:name].present?
      return 'Group message' if entry[:direct] && entry[:user_id].blank?

      user_name(entry[:user_id]) || 'Direct message'
    end

    def user_name(user_id)
      return nil if user_id.blank?

      Rails.cache.fetch("slack/user/#{connection.id}/#{user_id}", expires_in: IDENTITY_TTL) do
        profile = call('users.info', user: user_id)['user'] || {}
        profile.dig('profile', 'display_name').presence || profile['real_name'].presence || profile['name']
      end
    rescue Error
      nil
    end

    def list_conversations
      conversations = []
      cursor = nil

      MAX_PAGES.times do
        body = call('users.conversations', {
          types: 'im,mpim,private_channel,public_channel',
          exclude_archived: true,
          # A muted channel is one the user has said they don't want
          # to be nagged about; counting it would defeat that.
          exclude_muted: true,
          limit: PAGE_SIZE,
          cursor: cursor
        }.compact)

        conversations.concat(Array(body['channels']))
        cursor = body.dig('response_metadata', 'next_cursor').presence
        break if cursor.nil?
      end

      conversations
    end

    def direct?(conversation)
      conversation['is_im'] || conversation['is_mpim'] || false
    end

    def call(method, params = {})
      body = request { get(method, params) }
      guard_envelope(body, method)
      body
    end

    def get(method, params)
      http(base_url).get(method, params) do |request|
        request.headers['Authorization'] = "Bearer #{user_token}"
      end
    end

    # Slack signals failure inside a 200 response, so the envelope is the only
    # reliable signal — checking the HTTP status alone reads `invalid_auth` as
    # success.
    def guard_envelope(body, method)
      return if body.is_a?(Hash) && body['ok']

      error = body.is_a?(Hash) ? body['error'].to_s : ''
      raise RateLimited, "Slack rate limited #{method}" if error == 'ratelimited'
      raise AuthenticationError, scope_message(body, error) if AUTH_ERRORS.include?(error)

      raise Unavailable, "Slack #{method} failed: #{error.presence || 'unrecognised response'}"
    end

    def scope_message(body, error)
      return "Slack rejected the token: #{error}" unless error == 'missing_scope'

      "Slack token is missing the #{body['needed']} scope (it has #{body['provided']})"
    end

    # Slack has no official base-URL override, so unlike ANTHROPIC_BASE_URL this
    # exists purely so script/slack_stub.rb can stand in during development.
    # Leave it unset everywhere else.
    def base_url
      url = ENV.fetch('SLACK_BASE_URL', DEFAULT_BASE_URL).to_s.strip
      url.end_with?('/') ? url : "#{url}/"
    end

    def user_token
      credentials['user_token'].presence ||
        raise(AuthenticationError, 'no Slack user token stored for this connection')
    end
  end
end

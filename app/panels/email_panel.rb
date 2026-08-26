# frozen_string_literal: true

# Unread counts and message previews, one section per connected mailbox.
#
# Payload contract:
#   { accounts: [{ connection_id:, label:, unread_count:,
#                  messages: [{ uid:, message_id:, from:, subject:, received_at:,
#                               preview:, account: }] }],
#     total_unread:, partial: }
class EmailPanel < ApplicationPanel
  # Both speak to a mailbox; only how they authenticate differs.
  CLIENTS = { 'imap' => Integrations::Imap, 'gmail' => Integrations::Gmail }.freeze

  DEFAULT_LIMIT = 3

  # After a long outage a mailbox can come back with a hundred unread messages.
  # Announcing all of them would be a firehose, so only the newest few speak up.
  MAX_ANNOUNCEMENTS_PER_ACCOUNT = 3

  class << self
    def title = 'Email'
    def description = 'Unread counts and previews per mailbox'
    def required_providers = CLIENTS.keys
    def refresh_interval = 5.minutes
    def default_col_span = 2
  end

  def fetch
    accounts, partial = across_connections do |connection|
      result = CLIENTS.fetch(connection.provider).new(connection).unread(limit: limit)
      { connection_id: connection.id, label: connection.label }.merge(result)
    end

    {
      accounts: accounts,
      total_unread: accounts.sum { |account| account[:unread_count].to_i },
      partial: partial
    }
  end

  # Off by default (see NotificationPreference::KINDS) — most people don't want
  # a push per message — but wired so the preference is real when switched on.
  def notify(previous_data)
    seen = previously_seen(previous_data)

    Array(cached_data[:accounts]).each do |account|
      fresh = Array(account[:messages]).reject { |message| seen.include?(identity(message)) }
      fresh.first(MAX_ANNOUNCEMENTS_PER_ACCOUNT).each { |message| announce_message(account, message) }
    end
  end

  private

  def previously_seen(previous_data)
    Array(previous_data[:accounts])
      .flat_map { |account| Array(account[:messages]) }
      .to_set { |message| identity(message) }
  end

  # Message-ids survive a mailbox resync; UIDs don't, so they're only a fallback.
  def identity(message)
    message[:message_id].presence || "#{message[:account]}:#{message[:uid]}"
  end

  def announce_message(account, message)
    Notifications::Deliver.call(
      user,
      'email_received',
      Notifications::Deliver::Payload.new(
        title: message[:from].presence || account[:label],
        body: message[:subject].to_s.truncate(180),
        url: '/',
        tag: "email-#{account[:connection_id]}"
      ),
      dedupe_key: identity(message)
    )
  end

  def limit
    settings.fetch('limit', DEFAULT_LIMIT).to_i.clamp(1, 10)
  end
end

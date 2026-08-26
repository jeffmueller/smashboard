# frozen_string_literal: true

# One linked external account. A user can hold several per provider — two Slack
# workspaces, a Gmail and a Fastmail mailbox — which is why panels reference
# connections by id rather than by provider.
class Connection < ApplicationRecord
  # The catalogue in ConnectionProvider is the source of truth for which
  # providers exist and what each one needs.
  PROVIDERS = ConnectionProvider.keys

  STATUSES = %w[pending ok error].freeze

  belongs_to :user

  serialize :credentials, type: Hash, coder: JSON
  encrypts :credentials

  validates :provider, inclusion: { in: PROVIDERS }
  validates :label, presence: true, length: { maximum: 120 },
                    uniqueness: { scope: %i[user_id provider], case_sensitive: false }
  validates :status, inclusion: { in: STATUSES }

  scope :for_provider, ->(provider) { where(provider: provider) }
  scope :healthy, -> { where(status: 'ok') }

  def self.fields_for(provider)
    ConnectionProvider.find(provider)&.field_keys || { settings: [], credentials: [] }
  end

  def credential(key)
    credentials[key.to_s]
  end

  def mark_synced!
    update!(status: 'ok', last_synced_at: Time.current, last_error: nil, last_error_at: nil)
  end

  # `actionable` says whether the user can do anything about it. A dead OAuth
  # grant or a rejected password can be fixed; Google having a bad minute cannot,
  # and waking someone for that is just noise. The panel still shows the error
  # either way.
  def mark_failed!(error, actionable: true)
    was_already_failing = status == 'error'
    update!(status: 'error', last_error: error.to_s.truncate(1000), last_error_at: Time.current)
    notify_failure if actionable && !was_already_failing
  end

  def oauth?
    ConnectionProvider.find(provider)&.oauth?
  end

  # Straight into the authorization flow for a provider that has one, so fixing
  # it from the notification is a single tap.
  def repair_path
    definition = ConnectionProvider.find(provider)
    return '/connections' unless definition&.oauth?

    Rails.application.routes.url_helpers.public_send("oauth_#{definition.oauth}_path",
                                                     provider: provider, connection_id: id)
  end

  # At most one warning per connection per day: a panel refreshing every few
  # minutes against a dead server would otherwise be a notification firehose.
  def notify_failure
    Notifications::Deliver.call(
      user,
      'connection_failing',
      Notifications::Deliver::Payload.new(
        title: 'Connection problem',
        body: failure_body,
        url: repair_path,
        tag: "connection-#{id}"
      ),
      # The daily boundary has to be the user's, not the worker's.
      dedupe_key: "#{id}:#{user.zone.today.iso8601}"
    )
  rescue StandardError => e
    Rails.logger.warn("[connection:#{id}] failure notification failed: #{e.class}: #{e.message}")
  end

  def failure_body
    action = oauth? ? 'Tap to sign in again' : 'Tap to fix it'

    "#{label} stopped working: #{last_error}. #{action}.".truncate(180)
  end

  # Never let a credential hash reach a log, an API response or an exception
  # reporter.
  def as_json(options = {})
    super(options.merge(except: Array(options[:except]) + %w[credentials]))
  end
end

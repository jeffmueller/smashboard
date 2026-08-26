# frozen_string_literal: true

# Unread GitHub notifications across every connected account.
#
# Payload contract:
#   { notifications: [{ id:, title:, repository:, reason:, reason_label:, type:,
#                       url:, updated_at:, account: }],
#     unread_count:, capped:, partial: }
class GithubNotificationsPanel < ApplicationPanel
  DEFAULT_LIMIT = 8

  class << self
    def title = 'GitHub'
    def description = 'Unread GitHub notifications'
    def required_providers = %w[github]
    def refresh_interval = 5.minutes
    def default_col_span = 1
  end

  def fetch
    results, partial = across_connections { |connection| Integrations::Github.new(connection).notifications }
    notifications = results.flatten.sort_by { |item| item[:updated_at].to_s }.reverse

    {
      notifications: notifications.first(limit),
      unread_count: notifications.size,
      # A full page back from any account means there may well be more.
      capped: results.any? { |page| page.size >= Integrations::Github::PAGE_SIZE },
      partial: partial
    }
  end

  private

  def limit
    settings.fetch('limit', DEFAULT_LIMIT).to_i.clamp(1, 30)
  end
end

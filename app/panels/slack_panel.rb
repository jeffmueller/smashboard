# frozen_string_literal: true

# Unread Slack messages, one section per connected workspace.
#
# Payload contract:
#   { workspaces: [{ connection_id:, name:, url:, dm_unread:, channel_unread:,
#                    total_unread:, conversations_checked:, conversations_skipped:,
#                    top: [{ name:, direct:, unread: }] }],
#     total_unread:, dm_unread:, incomplete:, partial: }
class SlackPanel < ApplicationPanel
  class << self
    def title = 'Slack'
    def description = 'Unread messages across your workspaces'
    def required_providers = %w[slack]
    def refresh_interval = 5.minutes
    def default_col_span = 1
  end

  def fetch
    results, partial = across_connections do |connection|
      client = Integrations::Slack.new(connection)
      identity = client.workspace

      {
        connection_id: connection.id,
        name: identity[:team].presence || connection.label,
        url: identity[:url]
      }.merge(client.unread(budget: budget))
    end

    combine(results, partial)
  end

  private

  def combine(workspaces, partial)
    counted = workspaces.map { |workspace| workspace.merge(total_unread: total_for(workspace)) }

    {
      workspaces: counted.sort_by { |workspace| -workspace[:total_unread] },
      total_unread: counted.sum { |workspace| workspace[:total_unread] },
      dm_unread: counted.sum { |workspace| workspace[:dm_unread].to_i },
      # Slack has no bulk unread endpoint, so a large workspace may not be fully
      # counted. Say so rather than present a short number as the whole truth.
      incomplete: counted.any? { |workspace| workspace[:conversations_skipped].to_i.positive? },
      partial: partial
    }
  end

  def total_for(workspace)
    workspace[:dm_unread].to_i + workspace[:channel_unread].to_i
  end

  def budget
    settings.fetch('lookup_budget', Integrations::Slack::LOOKUP_BUDGET).to_i.clamp(5, 200)
  end
end

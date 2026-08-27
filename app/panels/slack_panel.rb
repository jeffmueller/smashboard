# frozen_string_literal: true

# Unread Slack messages, one section per connected workspace.
#
# Payload contract:
#   { workspaces: [{ connection_id:, name:, url:, dm_unread:, channel_unread:,
#                    total_unread:, conversations_checked:, conversations_skipped:,
#                    conversations_uncounted:, top: [{ name:, direct:, unread: }] }],
#     total_unread:, dm_unread:, incomplete:, uncounted:, partial: }
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
      # The total can fall short two ways, and both mean the same thing to a
      # reader: it is a floor, not the whole truth. Either the fan-out budget ran
      # out on a large workspace, or Slack returned no unread count for some
      # conversations — which is what a token missing the history scopes looks
      # like, since it affects every channel and no DM.
      incomplete: counted.any? { |workspace| short_count?(workspace) },
      # Split out from `incomplete` because the two have different answers: a
      # budget that ran out is nothing the reader can act on, whereas Slack
      # refusing to answer is fixed by reconnecting for the history scopes.
      uncounted: counted.sum { |workspace| workspace[:conversations_uncounted].to_i },
      partial: partial
    }
  end

  def short_count?(workspace)
    workspace[:conversations_skipped].to_i.positive? || workspace[:conversations_uncounted].to_i.positive?
  end

  def total_for(workspace)
    workspace[:dm_unread].to_i + workspace[:channel_unread].to_i
  end

  def budget
    settings.fetch('lookup_budget', Integrations::Slack::LOOKUP_BUDGET).to_i.clamp(5, 200)
  end
end

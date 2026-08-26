# frozen_string_literal: true

# Open pull requests waiting on you, and the ones you opened.
#
# Payload contract:
#   { pull_requests: [{ id:, title:, repository:, number:, url:, author:, draft:,
#                       comments:, relationship:, updated_at:, account: }],
#     review_requested_count:, mine_count:, partial: }
class GithubPullRequestsPanel < ApplicationPanel
  DEFAULT_LIMIT = 10

  class << self
    def title = 'Pull Requests'
    def description = 'Open pull requests awaiting you'
    def required_providers = %w[github]
    def refresh_interval = 10.minutes
    def default_col_span = 2
  end

  def fetch
    results, partial = across_connections { |connection| Integrations::Github.new(connection).pull_requests }
    pull_requests = sort(results.flatten)

    {
      pull_requests: pull_requests.first(limit),
      review_requested_count: pull_requests.count { |pr| pr[:relationship] == 'review_requested' },
      mine_count: pull_requests.count { |pr| pr[:relationship] == 'mine' },
      partial: partial
    }
  end

  # Fires only for review requests that weren't in the previous payload, so a
  # PR sitting in your queue for a week notifies once, not every refresh.
  def notify(previous_data)
    already_seen = Array(previous_data[:pull_requests])
                   .select { |pr| pr[:relationship] == 'review_requested' }
                   .to_set { |pr| pr[:url] }

    awaiting_review.reject { |pr| already_seen.include?(pr[:url]) }.each { |pr| announce_review_request(pr) }
  end

  private

  def awaiting_review
    Array(cached_data[:pull_requests]).select { |pr| pr[:relationship] == 'review_requested' }
  end

  def announce_review_request(pull_request)
    Notifications::Deliver.call(
      user,
      'github_review_requested',
      Notifications::Deliver::Payload.new(
        title: 'Review requested',
        body: "#{pull_request[:repository]}##{pull_request[:number]} · #{pull_request[:title]}".truncate(180),
        url: pull_request[:url],
        tag: "pr-#{pull_request[:id]}"
      ),
      dedupe_key: pull_request[:url].to_s
    )
  end

  # Someone waiting on your review is the actionable half of this panel, so it
  # sorts to the top regardless of how recently anything moved.
  def sort(pull_requests)
    pull_requests.sort_by do |pull_request|
      [pull_request[:relationship] == 'review_requested' ? 0 : 1, pull_request[:updated_at].to_s]
    end
  end

  def limit
    settings.fetch('limit', DEFAULT_LIMIT).to_i.clamp(1, 30)
  end
end

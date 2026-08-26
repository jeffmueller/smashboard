# frozen_string_literal: true

module GithubHelpers
  def stub_github(notifications: [], pull_requests: [])
    allow(Integrations::Github).to receive(:new)
      .and_return(instance_double(Integrations::Github,
                                  notifications: notifications,
                                  pull_requests: pull_requests))
  end

  def github_notification(id, updated_at, overrides = {})
    { id: id, title: "Notification #{id}", type: 'PullRequest', reason: 'mention',
      reason_label: 'Mentioned', repository: 'octocat/smashboard',
      url: "https://github.com/octocat/smashboard/pull/#{id}", updated_at: updated_at,
      account: 'Work' }.merge(overrides)
  end

  def github_pull_request(id, relationship, updated_at, overrides = {})
    { id: id, title: "PR #{id}", number: id, repository: 'octocat/smashboard',
      url: "https://github.com/octocat/smashboard/pull/#{id}", author: 'dana', draft: false,
      comments: 0, relationship: relationship, updated_at: updated_at,
      account: 'Work' }.merge(overrides)
  end
end

RSpec.configure { |config| config.include GithubHelpers }

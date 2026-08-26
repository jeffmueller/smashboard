# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GithubPullRequestsPanel do
  let(:user) { create(:user) }
  let!(:work) { create(:connection, user: user, provider: 'github', label: 'Work') }
  let(:panel) { user.panels.find_by!(kind: 'github_pull_requests') }

  it 'puts review requests above your own pull requests' do
    stub_github(pull_requests: [github_pull_request(1, 'mine', '2026-08-25T15:00:00Z'),
                                github_pull_request(2, 'review_requested', '2026-08-25T09:00:00Z')])

    payload = panel.presenter.fetch

    expect(payload[:pull_requests].pluck(:id)).to eq([2, 1])
    expect(payload[:review_requested_count]).to eq(1)
    expect(payload[:mine_count]).to eq(1)
  end

  describe 'review request notifications' do
    let!(:device) { create(:push_subscription, user: user) }

    before { capture_pushes }

    it 'raises an alarm the first time a review is requested' do
      stub_github(pull_requests: [github_pull_request(2, 'review_requested', '2026-08-25T09:00:00Z')])

      panel.presenter.refresh!

      expect(sent_pushes.size).to eq(1)
      message = JSON.parse(sent_pushes.first[:message])
      expect(message['title']).to eq('Review requested')
      expect(message['body']).to include('octocat/smashboard#2', 'PR 2')
      expect(message['url']).to eq('https://github.com/octocat/smashboard/pull/2')
    end

    # A PR sitting in your queue for a week should notify once, not hourly.
    it 'stays quiet on later refreshes for the same pull request' do
      stub_github(pull_requests: [github_pull_request(2, 'review_requested', '2026-08-25T09:00:00Z')])

      3.times { panel.presenter.refresh! }

      expect(sent_pushes.size).to eq(1)
    end

    it 'raises an alarm for a newly added review request' do
      stub_github(pull_requests: [github_pull_request(2, 'review_requested', '2026-08-25T09:00:00Z')])
      panel.presenter.refresh!

      stub_github(pull_requests: [github_pull_request(2, 'review_requested', '2026-08-25T09:00:00Z'),
                                  github_pull_request(3, 'review_requested', '2026-08-25T10:00:00Z')])
      panel.presenter.refresh!

      expect(sent_pushes.size).to eq(2)
    end

    it 'stays quiet about pull requests you opened yourself' do
      stub_github(pull_requests: [github_pull_request(1, 'mine', '2026-08-25T15:00:00Z')])

      panel.presenter.refresh!

      expect(sent_pushes).to be_empty
    end
  end
end

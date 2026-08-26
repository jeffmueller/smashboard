# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Github do
  let(:connection) do
    create(:connection, provider: 'github', label: 'Work GitHub',
                        settings: {}, credentials: { 'access_token' => 'ghp_secret' })
  end

  let(:client) { described_class.new(connection) }

  def json(body)
    { status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def notification(overrides = {})
    {
      id: '1', reason: 'review_requested', unread: true, updated_at: '2026-08-25T12:00:00Z',
      subject: { title: 'Add the calendar panel', type: 'PullRequest',
                 url: 'https://api.github.com/repos/octocat/smashboard/pulls/42' },
      repository: { full_name: 'octocat/smashboard', html_url: 'https://github.com/octocat/smashboard' }
    }.deep_merge(overrides)
  end

  describe '#notifications' do
    # Octokit uses the `token` scheme for personal access tokens, which GitHub
    # accepts for both classic and fine-grained ones.
    it 'authenticates with the stored token' do
      request = stub_request(:get, %r{api\.github\.com/notifications})
                .with(headers: { 'Authorization' => 'token ghp_secret' })
                .to_return(json([]))

      client.notifications

      expect(request).to have_been_made
    end

    it 'normalises a pull request notification, converting the API URL to a web one' do
      stub_request(:get, %r{/notifications}).to_return(json([notification]))

      result = client.notifications.first

      expect(result).to include(
        title: 'Add the calendar panel',
        repository: 'octocat/smashboard',
        reason: 'review_requested',
        reason_label: 'Review requested',
        url: 'https://github.com/octocat/smashboard/pull/42',
        account: 'Work GitHub'
      )
    end

    it 'converts a commit subject URL' do
      stub_request(:get, %r{/notifications}).to_return(json([
                                                              notification(subject: { type: 'Commit',
                                                                                      url: 'https://api.github.com/repos/octocat/smashboard/commits/abc123' })
                                                            ]))

      expect(client.notifications.first[:url]).to eq('https://github.com/octocat/smashboard/commit/abc123')
    end

    it 'leaves an issue URL alone apart from the host' do
      stub_request(:get, %r{/notifications}).to_return(json([
                                                              notification(subject: { type: 'Issue', url: 'https://api.github.com/repos/octocat/smashboard/issues/7' })
                                                            ]))

      expect(client.notifications.first[:url]).to eq('https://github.com/octocat/smashboard/issues/7')
    end

    # A release's API id is not its web tag, so that path would 404.
    it 'sends release and discussion notifications to the repo section instead' do
      stub_request(:get, %r{/notifications}).to_return(json([
                                                              notification(id: '1', subject: { type: 'Release',
                                                                                               url: 'https://api.github.com/repos/octocat/smashboard/releases/99' }),
                                                              notification(id: '2',
                                                                           subject: {
                                                                             type: 'Discussion', url: nil
                                                                           })
                                                            ]))

      urls = client.notifications.pluck(:url)

      expect(urls).to eq(['https://github.com/octocat/smashboard/releases',
                          'https://github.com/octocat/smashboard/discussions'])
    end

    it 'falls back to the repository when the subject URL is not repo-scoped' do
      stub_request(:get, %r{/notifications}).to_return(json([
                                                              notification(subject: { type: 'Issue', url: 'https://api.github.com/something/else' })
                                                            ]))

      expect(client.notifications.first[:url]).to eq('https://github.com/octocat/smashboard')
    end

    it 'humanises an unrecognised reason' do
      stub_request(:get, %r{/notifications}).to_return(json([notification(reason: 'some_new_reason')]))

      expect(client.notifications.first[:reason_label]).to eq('Some new reason')
    end
  end

  describe '#pull_requests' do
    def search_result(overrides = {})
      {
        id: 1, number: 42, title: 'Add the calendar panel',
        html_url: 'https://github.com/octocat/smashboard/pull/42',
        repository_url: 'https://api.github.com/repos/octocat/smashboard',
        user: { login: 'dana' }, comments: 3, updated_at: '2026-08-25T12:00:00Z'
      }.merge(overrides)
    end

    before { stub_request(:get, %r{api\.github\.com/user\z}).to_return(json({ login: 'octocat' })) }

    def stub_search(review_requested: [], authored: [])
      stub_request(:get, %r{/search/issues}).with(query: hash_including('q' => /review-requested:octocat/))
                                            .to_return(json({ items: review_requested }))
      stub_request(:get, %r{/search/issues}).with(query: hash_including('q' => /author:octocat/))
                                            .to_return(json({ items: authored }))
    end

    it 'resolves the authenticated login and searches on it' do
      stub_search

      client.pull_requests

      expect(a_request(:get, %r{/search/issues}).with(query: hash_including('q' => /review-requested:octocat/)))
        .to have_been_made
    end

    it 'tags which relationship each pull request has' do
      stub_search(review_requested: [search_result(id: 1)],
                  authored: [search_result(id: 2, html_url: 'https://github.com/octocat/smashboard/pull/43')])

      expect(client.pull_requests.pluck(:relationship)).to eq(%w[review_requested mine])
    end

    it 'normalises a search result' do
      stub_search(review_requested: [search_result])

      expect(client.pull_requests.first).to include(
        number: 42, repository: 'octocat/smashboard', author: 'dana', comments: 3,
        url: 'https://github.com/octocat/smashboard/pull/42', account: 'Work GitHub'
      )
    end

    # GitHub omits `draft` rather than nulling it on older results.
    it 'defaults a missing draft flag to false' do
      stub_search(review_requested: [search_result])

      expect(client.pull_requests.first[:draft]).to be(false)
    end

    it 'keeps the review-requested relationship when a PR is both' do
      same = search_result
      stub_search(review_requested: [same], authored: [same])

      results = client.pull_requests

      expect(results.size).to eq(1)
      expect(results.first[:relationship]).to eq('review_requested')
    end
  end

  describe 'failures' do
    it 'raises AuthenticationError with no token stored' do
      connection.update!(credentials: {})

      expect { client.notifications }
        .to raise_error(Integrations::Base::AuthenticationError, /no GitHub token/)
    end

    it 'raises AuthenticationError on a rejected token' do
      stub_request(:get, %r{/notifications}).to_return(status: 401, body: '{}')

      expect { client.notifications }
        .to raise_error(Integrations::Base::AuthenticationError, /rejected/)
    end

    # Octokit::TooManyRequests subclasses Octokit::Forbidden, so rescue order
    # decides whether a rate limit is reported as a bad token.
    it 'distinguishes a rate limit from a scope problem' do
      stub_request(:get, %r{/notifications})
        .to_return(status: 403, body: { message: 'API rate limit exceeded for user' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect { client.notifications }.to raise_error(Integrations::Base::RateLimited, /rate limit/)
    end

    it 'reports a plain 403 as a scope problem' do
      stub_request(:get, %r{/notifications})
        .to_return(status: 403, body: { message: 'Resource not accessible by personal access token' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect { client.notifications }
        .to raise_error(Integrations::Base::AuthenticationError, /scopes/)
    end

    it 'reports a server error as unavailable' do
      stub_request(:get, %r{/notifications}).to_return(status: 500, body: '{}')

      expect { client.notifications }.to raise_error(Integrations::Base::Unavailable)
    end
  end

  describe 'GitHub Enterprise' do
    let(:connection) do
      create(:connection, provider: 'github', label: 'Enterprise',
                          settings: { 'api_endpoint' => 'https://ghe.example.com/api/v3/' },
                          credentials: { 'access_token' => 'ghp_secret' })
    end

    it 'talks to the configured API host' do
      request = stub_request(:get, %r{ghe\.example\.com/api/v3/notifications}).to_return(json([]))

      client.notifications

      expect(request).to have_been_made
    end

    # Links must stay on the enterprise host, not bounce to github.com.
    it 'builds web URLs from the repository host' do
      enterprise = notification(
        subject: { type: 'PullRequest',
                   url: 'https://ghe.example.com/api/v3/repos/octocat/smashboard/pulls/42' },
        repository: { full_name: 'octocat/smashboard', html_url: 'https://ghe.example.com/octocat/smashboard' }
      )
      stub_request(:get, %r{ghe\.example\.com/api/v3/notifications}).to_return(json([enterprise]))

      expect(client.notifications.first[:url]).to eq('https://ghe.example.com/octocat/smashboard/pull/42')
    end
  end
end

# frozen_string_literal: true

module Integrations
  # GitHub via octokit, authenticated with a personal access token.
  #
  # Attribute access goes through Sawyer::Resource's `[]` rather than method
  # calls, because GitHub omits keys rather than nulling them — `item.draft`
  # raises on a search result that predates the draft field, while
  # `item[:draft]` simply returns nil.
  class Github < Base
    # One page. Callers decide how many to display; the full page is returned so
    # a count can be honest about how much is waiting, and PAGE_SIZE lets them
    # tell "exactly a page" from "we stopped counting".
    PAGE_SIZE = 50
    MAX_PULL_REQUESTS = 20
    LOGIN_TTL = 12.hours

    REASON_LABELS = {
      'review_requested' => 'Review requested',
      'mention' => 'Mentioned',
      'team_mention' => 'Team mentioned',
      'assign' => 'Assigned',
      'author' => 'Your thread',
      'comment' => 'New comment',
      'ci_activity' => 'CI',
      'state_change' => 'State changed',
      'subscribed' => 'Watching',
      'manual' => 'Subscribed',
      'security_alert' => 'Security alert'
    }.freeze

    # Notification subjects arrive as API URLs. These types have no web page at
    # the corresponding path at all, so they link to the repo section instead.
    SECTION_FOR_TYPE = {
      'Release' => 'releases',
      'Discussion' => 'discussions',
      'CheckSuite' => 'actions'
    }.freeze

    def notifications
      guard do
        client.notifications(all: false, per_page: PAGE_SIZE)
              .map { |notification| normalize_notification(notification) }
      end
    end

    # Both the pull requests you opened and the ones waiting on your review.
    # Listed review-requested first so that, in the rare case a PR is both, it
    # keeps the relationship that actually needs action.
    def pull_requests
      guard do
        me = login
        requested = search("is:open is:pr archived:false review-requested:#{me}", 'review_requested')
        mine = search("is:open is:pr archived:false author:#{me}", 'mine')

        (requested + mine).uniq { |pull_request| pull_request[:url] }
      end
    end

    def login
      @login ||= Rails.cache.fetch("github/login/#{connection.id}", expires_in: LOGIN_TTL) do
        guard { client.user[:login] }
      end
    end

    private

    def search(query, relationship)
      results = client.search_issues(query, per_page: MAX_PULL_REQUESTS)

      Array(results[:items]).map { |item| normalize_pull_request(item, relationship) }
    end

    def normalize_notification(notification)
      subject = notification[:subject]
      repository = notification[:repository]

      {
        id: notification[:id],
        title: subject&.[](:title).presence || '(untitled)',
        type: subject&.[](:type),
        reason: notification[:reason],
        reason_label: REASON_LABELS.fetch(notification[:reason], notification[:reason].to_s.humanize),
        repository: repository&.[](:full_name),
        url: web_url_for(subject, repository),
        updated_at: notification[:updated_at]&.iso8601,
        account: connection.label
      }
    end

    def normalize_pull_request(item, relationship)
      {
        id: item[:id],
        title: item[:title],
        number: item[:number],
        repository: repository_from(item[:repository_url]),
        url: item[:html_url],
        author: item[:user]&.[](:login),
        draft: item[:draft] || false,
        comments: item[:comments].to_i,
        relationship: relationship,
        updated_at: item[:updated_at]&.iso8601,
        account: connection.label
      }
    end

    # api.github.com/repos/o/r/pulls/1 -> github.com/o/r/pull/1. The REST paths
    # are pluralised where the web paths are not.
    def web_url_for(subject, repository)
      repository_url = repository&.[](:html_url).to_s
      section = SECTION_FOR_TYPE[subject&.[](:type)]
      return [repository_url, section].compact_blank.join('/') if section

      api_url = subject&.[](:url).to_s
      return repository_url if api_url.blank?

      path = api_url.sub(%r{\Ahttps?://.+?/repos/}, '')
      return repository_url if path == api_url || repository_url.blank?

      # Derive the web host from the repository rather than assuming github.com,
      # so GitHub Enterprise links stay on the right host.
      host = repository_url.sub(%r{(\Ahttps?://[^/]+).*}, '\\1')
      "#{host}/#{path.sub('/pulls/', '/pull/').sub('/commits/', '/commit/')}"
    end

    def repository_from(url)
      url.to_s.split('/repos/').last.presence
    end

    def client
      @client ||= Octokit::Client.new(
        access_token: access_token,
        api_endpoint: api_endpoint,
        auto_paginate: false,
        connection_options: { request: { open_timeout: OPEN_TIMEOUT, timeout: READ_TIMEOUT } }
      )
    end

    # Blank means github.com. Set it to a GitHub Enterprise API root
    # (https://ghe.example.com/api/v3/) to point a connection at a private host.
    def api_endpoint
      setting('api_endpoint').presence || Octokit.api_endpoint
    end

    def access_token
      credentials['access_token'].presence ||
        raise(AuthenticationError, 'no GitHub token stored for this connection')
    end

    # Octokit::TooManyRequests is a subclass of Octokit::Forbidden, so it has to
    # be rescued first or a rate limit would be reported as a bad token.
    def guard
      yield
    rescue Octokit::Unauthorized
      raise AuthenticationError, 'GitHub rejected this token'
    rescue Octokit::TooManyRequests
      raise RateLimited, 'GitHub rate limit reached'
    rescue Octokit::Forbidden
      raise AuthenticationError, "GitHub refused the request — check the token's scopes"
    rescue Octokit::Error => e
      raise Unavailable, "GitHub error: #{e.class.name.demodulize}"
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      raise Unavailable, "GitHub unreachable: #{e.message}"
    end
  end
end

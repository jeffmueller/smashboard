# frozen_string_literal: true

module Integrations
  # A breaking-news feed behind a shared password.
  #
  # The contract, which any server can implement:
  #
  #   GET <feed url>/api/breaking-news
  #   -> { headline, summary, mentionCount, sources: [], articles: [{ source, title, link }] }
  #
  # Both the host and the name of the cookie the password is presented in are
  # configuration rather than constants: they describe whichever service is
  # being read, not this app. A feed that needs no password simply gets no
  # cookie.
  #
  # Worth doing on the feed's side: accept a dedicated machine token instead, so
  # a client isn't holding the same password a human logs in with.
  class NewsFeed < Base
    PATH = '/api/breaking-news'

    # Overridden per connection by the `cookie_name` setting; a feed that names
    # its session cookie something else says so there.
    DEFAULT_AUTH_COOKIE = 'auth'

    def breaking_news
      body = request { get(PATH) }
      return { story: nil, fetched_at: Time.current.iso8601 } if body.blank?

      { story: normalize(body), fetched_at: Time.current.iso8601 }
    end

    private

    # Raised rather than defaulted: there is no sensible host to guess for a
    # feed somebody else runs, and Unavailable parks the panel with a readable
    # message instead of letting Faraday fail on a nil URL.
    def base_url
      url = setting('base_url').presence || ENV.fetch('NEWS_FEED_BASE_URL', nil)
      raise Unavailable, 'no news feed URL configured' if url.blank?

      url
    end

    def auth_cookie
      setting('cookie_name').presence || ENV.fetch('NEWS_FEED_AUTH_COOKIE', DEFAULT_AUTH_COOKIE)
    end

    def password
      credentials['password'].presence || ENV.fetch('NEWS_FEED_PASSWORD', nil)
    end

    def get(path)
      http(base_url).get(path) do |req|
        req.headers['Cookie'] = "#{auth_cookie}=#{password}" if password.present?
        req.headers['Accept'] = 'application/json'
      end
    end

    # The endpoint speaks camelCase; the rest of smashboard speaks snake_case.
    def normalize(body)
      {
        headline: body['headline'],
        summary: body['summary'],
        mention_count: body['mentionCount'],
        sources: Array(body['sources']),
        articles: Array(body['articles']).map do |article|
          { source: article['source'], title: article['title'], link: article['link'] }
        end
      }
    end
  end
end

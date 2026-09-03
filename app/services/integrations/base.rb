# frozen_string_literal: true

module Integrations
  # Shared HTTP plumbing for every third-party client.
  #
  # Every integration is constructed from a Connection, which carries the
  # encrypted credentials and the non-secret settings for one linked account.
  # Clients raise Integrations::Error subclasses; ApplicationPanel#refresh!
  # catches those and parks the panel in an error state rather than failing the
  # page or burning the job's retry budget.
  class Base
    class Error < StandardError; end
    class AuthenticationError < Error; end
    class RateLimited < Error; end
    class Unavailable < Error; end

    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 12

    attr_reader :connection

    def initialize(connection)
      @connection = connection
    end

    # Runs the request and normalises transport failures into Integrations
    # errors so callers never have to rescue Faraday directly.
    def self.call(connection, ...)
      new(connection).call(...)
    end

    private

    def credentials
      connection.credentials
    end

    def setting(key, default = nil)
      connection.settings.fetch(key.to_s, default)
    end

    # The zone a *floating* value from this account means. A calendar date with
    # no time and no zone — an all-day event — is not an instant until somebody
    # says where it is being read, and the user's zone is the one the dashboard
    # is rendered in.
    def zone
      connection.user.zone
    end

    def http(base_url, &)
      Faraday.new(url: base_url) do |f|
        f.request :json
        f.request :retry, max: 2, interval: 0.25, backoff_factor: 2,
                          retry_statuses: [429, 500, 502, 503, 504],
                          exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed]
        f.response :json, content_type: /\bjson/
        f.options.open_timeout = OPEN_TIMEOUT
        f.options.timeout = READ_TIMEOUT
        yield f if block_given?
      end
    end

    # Performs the request and maps the response.
    #
    # faraday-retry does not return once it has spent its attempts on a
    # retryable status — it raises Faraday::RetriableResponse carrying the last
    # response. Left alone that escapes as a Faraday error rather than an
    # Integrations::Base::Error, which defeats every rescue keyed on the latter:
    # a 503 from one account would abort a whole multi-account panel instead of
    # being isolated to that account.
    def request(&)
      handle(response_for(&))
    end

    # Callers that need the response itself rather than its parsed body — an
    # image proxy wanting the content type, say — go through this.
    def response_for
      yield
    rescue Faraday::RetriableResponse => e
      e.response
    end

    def handle(response)
      case response.status
      when 200..299 then response.body
      when 401, 403 then raise AuthenticationError, "#{self.class.name}: credentials rejected (#{response.status})"
      when 429 then raise RateLimited, "#{self.class.name}: rate limited"
      else raise Unavailable, "#{self.class.name}: unexpected status #{response.status}"
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      raise Unavailable, "#{self.class.name}: #{e.message}"
    end
  end
end

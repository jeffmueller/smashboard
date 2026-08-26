# frozen_string_literal: true

# Base class for every dashboard panel.
#
# Panels come in two flavours:
#
#   local  — reads this app's own database (clock, countdowns, todos). Cheap, so
#            it's computed fresh on every render and never cached.
#   remote — calls a third-party API (email, GitHub, Slack, news, weather).
#            RefreshPanelJob fetches out of band and writes the result to
#            panel.data, so rendering the dashboard never blocks on a network
#            call and a failing integration degrades to stale data rather than
#            a broken page.
#
# A panel class is found by convention: Panel#kind "github_pull_requests"
# resolves to GithubPullRequestsPanel in this directory.
class ApplicationPanel
  class UnknownPanel < StandardError; end

  attr_reader :panel

  delegate :user, :settings, to: :panel

  class << self
    def for(panel)
      klass = "#{panel.kind.camelize}Panel".safe_constantize
      raise UnknownPanel, "no panel class registered for #{panel.kind.inspect}" if klass.nil?

      klass.new(panel)
    end

    def all
      Panel::KINDS.map { |kind| "#{kind.camelize}Panel".safe_constantize }.compact
    end

    def kind
      name.delete_suffix('Panel').underscore
    end

    def title
      kind.humanize
    end

    # Overridden by remote panels to declare which Connection providers they
    # need before they can show anything.
    def required_providers
      []
    end

    def remote?
      required_providers.any?
    end

    # Panels whose integration is scaffolded but not yet wired up. They render
    # a placeholder and are skipped by the refresh scheduler, so a half-built
    # panel never sits in a scary error state.
    def pending?
      false
    end

    def refresh_interval
      5.minutes
    end

    def default_col_span
      1
    end

    def default_row_span
      1
    end

    def description
      ''
    end
  end

  def initialize(panel)
    @panel = panel
  end

  # What the view renders. Local panels compute it; remote panels read the last
  # good fetch.
  def view_data
    self.class.remote? ? cached_data : build
  end

  # Local panels implement this.
  def build
    raise NotImplementedError, "#{self.class} must implement #build"
  end

  # Remote panels implement this; it is only ever called from RefreshPanelJob.
  def fetch
    raise NotImplementedError, "#{self.class} must implement #fetch"
  end

  def refresh!
    return false unless self.class.remote?
    return false if self.class.pending?

    panel.update!(data_status: 'refreshing')
    previous_data = panel.data.deep_symbolize_keys
    payload = fetch
    panel.update!(data: payload, data_fetched_at: Time.current, data_status: 'ok', last_error: nil)
    deliver_notifications(previous_data)
    true
  rescue StandardError => e
    # A dead integration should leave the panel stale and flagged, not raise the
    # dashboard down or spin the job through its whole retry budget.
    Rails.logger.warn("[panel:#{panel.kind}##{panel.id}] refresh failed: #{e.class}: #{e.message}")
    panel.update!(data_status: 'error', last_error: "#{e.class}: #{e.message}".truncate(1000))
    false
  end

  # Called after a successful refresh with the data this panel held before.
  # Panels that should raise an alarm on a change (a new breaking headline)
  # override this; a failure here must never fail the refresh itself.
  def notify(previous_data); end

  # Deliberately not named `announce`: panels define their own announce-ish
  # private helpers, and an arity-mismatched override of this wrapper fails
  # inside refresh!'s rescue, which turns a notification bug into a silent
  # panel error.
  def deliver_notifications(previous_data)
    notify(previous_data)
  rescue StandardError => e
    Rails.logger.warn("[panel:#{panel.kind}##{panel.id}] notification failed: #{e.class}: #{e.message}")
  end

  # Runs the block once per connected account, isolating failures: a dead
  # account marks itself, drops out, and the panel still renders whatever the
  # others returned. Only every account failing is a real error.
  #
  # Returns [results_from_healthy_accounts, partial?].
  def across_connections
    errors = []

    results = connections.map do |connection|
      value = yield(connection)
      connection.mark_synced!
      value
    rescue Integrations::Base::Error => e
      # Only an authentication failure is something the user can act on; a
      # timeout or a 503 will very likely fix itself before they read about it.
      connection.mark_failed!(e.message, actionable: e.is_a?(Integrations::Base::AuthenticationError))
      errors << "#{connection.label}: #{e.message}"
      nil
    end

    succeeded = results.compact

    # `results.size.positive?` rather than `results.any?`: a failed account
    # contributes nil, and `[nil].any?` is false, which would skip this branch
    # exactly when it matters most.
    raise Integrations::Base::Unavailable, errors.first if succeeded.empty? && results.size.positive?

    [succeeded, succeeded.size < results.size]
  end

  def connections
    return Connection.none if self.class.required_providers.empty?

    user.connections.where(provider: self.class.required_providers)
  end

  def configured?
    self.class.required_providers.empty? || connections.exists?
  end

  def cached_data
    panel.data.deep_symbolize_keys
  end

  # Panels that need per-second precision in the browser hand the client an
  # absolute ISO timestamp and let a Stimulus controller do the ticking; the
  # server never re-renders once a second.
  delegate :zone, to: :user
end

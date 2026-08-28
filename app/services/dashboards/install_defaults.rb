# frozen_string_literal: true

module Dashboards
  # Gives a user a dashboard that already looks like something. Panels whose
  # integrations aren't connected yet render an inviting "connect this" state
  # rather than being absent, which is how a user discovers what's available.
  #
  # Additive, and run on every dashboard render rather than only at signup: when
  # a new panel kind ships, existing users get it too. Removing a panel in the
  # UI hides it, which keeps the row, so nothing a user has turned off comes
  # back. (Destroying a panel row outright — only reachable through the API —
  # does mean it reappears here.)
  class InstallDefaults
    LAYOUT = %w[
      countdowns
      calendar
      todos
      habits
      bookmarks
      email
      news
      github_notifications
      github_pull_requests
      slack
      weather
      claude_usage
      cameras
    ].freeze

    def initialize(user)
      @user = user
    end

    def call
      installed = @user.panels.pluck(:kind).to_set
      missing = LAYOUT.reject { |kind| installed.include?(kind) }
      return if missing.empty?

      # New panels land at the end of the board; a new user's whole layout is
      # "missing", so they get LAYOUT's own order from position zero.
      position = @user.panels.next_position

      missing.each do |kind|
        klass = "#{kind.camelize}Panel".safe_constantize
        next if klass.nil?

        @user.panels.create!(
          kind: kind,
          position: position,
          col_span: klass.default_col_span,
          row_span: klass.default_row_span
        )
        position += 1
      end
    end
  end
end

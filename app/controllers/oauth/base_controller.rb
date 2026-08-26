# frozen_string_literal: true

module Oauth
  # Shared authorization-code plumbing. Subclasses name the service and the
  # provider key; everything about state, session and storage lives here so the
  # security-critical part exists once.
  class BaseController < ApplicationController
    STATE_KEY = :oauth_state
    PROVIDER_KEY = :oauth_provider
    CONNECTION_KEY = :oauth_connection_id

    def authorize
      provider = requested_provider
      return redirect_to connections_path, alert: "That isn't something you sign in to." if provider.nil?
      return redirect_to connections_path, alert: configuration_message unless service.configured?

      redirect_to service.authorize_url(redirect_uri: callback_url, state: begin_flow(provider),
                                        scopes: provider.oauth_scopes),
                  allow_other_host: true
    end

    def callback
      provider_key = session.delete(PROVIDER_KEY)
      connection_id = session.delete(CONNECTION_KEY)
      expected_state = session.delete(STATE_KEY)

      return redirect_to connections_path, alert: 'Sign-in was cancelled.' if params[:error].present?
      return redirect_to connections_path, alert: 'That sign-in could not be verified.' unless
        valid_state?(expected_state) && provider_matches?(provider_key)

      store(service.exchange(code: params[:code], redirect_uri: callback_url), provider_key, connection_id)
    rescue service::Error => e
      redirect_to connections_path, alert: e.message
    rescue ActiveRecord::RecordInvalid => e
      # Reaching here means a token was obtained but couldn't be stored. Better
      # to say so than to answer a successful sign-in with a 500.
      redirect_to connections_path,
                  alert: "That account could not be saved: #{e.record.errors.full_messages.to_sentence}"
    end

    private

    def begin_flow(provider)
      state = SecureRandom.urlsafe_base64(32)
      session[STATE_KEY] = state
      session[PROVIDER_KEY] = provider.key
      # Remembered so the callback knows whether it is re-authorizing an
      # existing connection or making a new one.
      session[CONNECTION_KEY] = current_user.connections.find_by(id: params[:connection_id])&.id
      state
    end

    def requested_provider
      provider = ConnectionProvider.find(params.expect(:provider))

      provider if provider&.oauth == oauth_key
    end

    # The state parameter is the only thing preventing an attacker from having
    # their own account silently connected to somebody else's dashboard.
    def valid_state?(expected)
      expected.present? && params[:state].present? &&
        ActiveSupport::SecurityUtils.secure_compare(expected, params[:state].to_s)
    end

    # Every flow shares one session key for its state, so a state minted by the
    # Google flow will match here too. Without this check a Slack callback
    # carrying that state would store a Slack token on a google_calendar
    # connection — a valid-looking record that could never work.
    def provider_matches?(provider_key)
      ConnectionProvider.find(provider_key)&.oauth == oauth_key
    end

    def store(result, provider_key, connection_id)
      connection = existing_connection(connection_id, provider_key, result) ||
                   current_user.connections.new(provider: provider_key, settings: {})

      connection.settings = connection.settings.merge('external_id' => result.external_id) if
        result.external_id.present?
      connection.label = connection.label.presence || available_label(provider_key, result)
      connection.credentials = connection.credentials.merge(result.credentials)
      connection.status = 'pending'
      connection.authorized_at = Time.current
      connection.save!

      redirect_to connections_path, notice: "Connected #{connection.label}."
    end

    # Which connection this sign-in belongs to, if any.
    #
    # Identity is the external account — a Slack team id, a Google address —
    # rather than the label, so a second workspace becomes a second connection
    # while re-authorizing the first refreshes it in place instead of failing
    # the label uniqueness check.
    def existing_connection(connection_id, provider_key, result)
      # A reconnect names the connection it is refreshing, which wins: the user
      # asked for that one specifically.
      explicit = current_user.connections.find_by(id: connection_id)
      return explicit if explicit
      return nil if result.external_id.blank?

      current_user.connections
                  .for_provider(provider_key)
                  .where("settings->>'external_id' = ?", result.external_id)
                  .first
    end

    # Labels are unique per provider, and two accounts can genuinely present the
    # same name, so a colliding one is numbered rather than rejected.
    def available_label(provider_key, result)
      base = result.label.presence || default_label
      taken = current_user.connections.for_provider(provider_key).pluck(:label).to_set(&:downcase)
      return base unless taken.include?(base.downcase)

      suffix = 2
      suffix += 1 while taken.include?("#{base} (#{suffix})".downcase)
      "#{base} (#{suffix})"
    end

    def default_label
      ConnectionProvider.find(session[PROVIDER_KEY])&.label || 'Connection'
    end
  end
end

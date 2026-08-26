# frozen_string_literal: true

module Integrations
  # Home Assistant's REST API, authenticated with a long-lived access token.
  #
  # Cameras are read through HA rather than spoken to directly: HA already holds
  # the per-camera credentials and normalises Reolink, ONVIF and the rest behind
  # one `camera_proxy` endpoint, so smashboard needs no RTSP handling and no
  # camera passwords of its own.
  class HomeAssistant < Base
    Snapshot = Struct.new(:body, :content_type, keyword_init: true)

    CAMERA_PREFIX = 'camera.'

    # Anything proxied has to match this. It is the only thing standing between
    # a URL parameter and an arbitrary Home Assistant endpoint, so it is
    # deliberately strict rather than merely a prefix check.
    ENTITY_ID = /\Acamera\.[a-z0-9_]+\z/

    UNAVAILABLE_STATES = %w[unavailable unknown].freeze

    def cameras
      states = request { authorized_get('api/states') }

      Array(states)
        .select { |state| state['entity_id'].to_s.start_with?(CAMERA_PREFIX) }
        .map { |state| normalize(state) }
        .select { |camera| permitted?(camera[:entity_id]) }
        .sort_by { |camera| ordering(camera[:entity_id]) }
    end

    def snapshot(entity_id)
      raise ArgumentError, "not a camera entity: #{entity_id}" unless entity_id.to_s.match?(ENTITY_ID)

      response = response_for { authorized_get("api/camera_proxy/#{entity_id}") }
      handle(response)

      Snapshot.new(
        body: response.body,
        content_type: response.headers['content-type'].presence || 'image/jpeg'
      )
    end

    private

    def normalize(state)
      entity_id = state['entity_id']
      attributes = state['attributes'] || {}

      {
        entity_id: entity_id,
        name: attributes['friendly_name'].presence || entity_id.delete_prefix(CAMERA_PREFIX).humanize,
        state: state['state'],
        available: UNAVAILABLE_STATES.exclude?(state['state'].to_s),
        updated_at: state['last_updated']
      }
    end

    # A blank entity_ids setting means "every camera HA knows about"; otherwise
    # the setting picks which ones appear, and in what order.
    def permitted?(entity_id)
      chosen.empty? || chosen.include?(entity_id)
    end

    def ordering(entity_id)
      chosen.empty? ? [0, entity_id] : [chosen.index(entity_id) || chosen.size, entity_id]
    end

    def chosen
      @chosen ||= begin
        raw = setting('entity_ids')
        (raw.is_a?(String) ? raw.split(',') : Array(raw)).map(&:strip).compact_blank
      end
    end

    def authorized_get(path)
      http(base_url).get(path) do |request|
        request.headers['Authorization'] = "Bearer #{access_token}"
      end
    end

    # Trailing slash, and paths without a leading one: Faraday resolves a
    # leading-slash path as absolute and would drop any path the instance is
    # served under (a reverse proxy at /homeassistant/, say).
    def base_url
      url = setting('base_url').to_s.strip
      raise Unavailable, 'no Home Assistant URL configured' if url.blank?

      url.end_with?('/') ? url : "#{url}/"
    end

    def access_token
      credentials['access_token'].presence ||
        raise(AuthenticationError, 'no Home Assistant token stored for this connection')
    end
  end
end

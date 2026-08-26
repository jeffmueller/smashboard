# frozen_string_literal: true

# Live snapshots from cameras Home Assistant already knows about.
#
# The cached payload is only the *list* of cameras, which changes rarely. The
# images themselves are fetched by the browser from this app's own snapshot
# proxy and refreshed client-side, so the panel doesn't have to re-render — and
# no image bytes ever pass through the panel cache.
#
# Payload contract:
#   { cameras: [{ entity_id:, name:, state:, available:, updated_at:,
#                 connection_id: }],
#     refresh_seconds:, partial: }
class CamerasPanel < ApplicationPanel
  DEFAULT_REFRESH_SECONDS = 30

  class << self
    def title = 'Cameras'
    def description = 'Live snapshots from your cameras via Home Assistant'
    def required_providers = %w[home_assistant]
    # The camera list, not the pictures.
    def refresh_interval = 15.minutes
    def default_col_span = 2
    def default_row_span = 2
  end

  def fetch
    results, partial = across_connections do |connection|
      Integrations::HomeAssistant.new(connection).cameras.map do |camera|
        camera.merge(connection_id: connection.id)
      end
    end

    { cameras: results.flatten, refresh_seconds: refresh_seconds, partial: partial }
  end

  private

  # Fast enough to feel live, slow enough not to hammer a Raspberry Pi.
  def refresh_seconds
    settings.fetch('refresh_seconds', DEFAULT_REFRESH_SECONDS).to_i.clamp(5, 600)
  end
end

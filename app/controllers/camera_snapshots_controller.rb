# frozen_string_literal: true

# Proxies a single camera frame from Home Assistant.
#
# The browser never talks to Home Assistant directly, for two reasons: the
# long-lived token would have to be handed to the client, and HA usually lives
# on a home LAN the viewer's phone can't reach. Fetching server-side solves
# both, at the cost of one Puma thread for the duration of the frame.
class CameraSnapshotsController < ApplicationController
  def show
    connection = current_user.connections.find_by!(id: params.expect(:connection_id), provider: 'home_assistant')
    snapshot = Integrations::HomeAssistant.new(connection).snapshot(params[:entity_id])

    # Frames are per-viewer and immediately stale; nothing should hold on to one.
    response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, private'
    send_data snapshot.body, type: snapshot.content_type, disposition: 'inline'
  rescue ArgumentError
    head :bad_request
  rescue Integrations::Base::Error => e
    # A dead camera is an everyday event, not an exception worth raising: the
    # view swaps in an offline placeholder when the image fails to load.
    Rails.logger.info("[cameras] snapshot failed for #{params[:entity_id]}: #{e.message}")
    head :bad_gateway
  end
end

# frozen_string_literal: true

# Fetches one remote panel's data out of band and pushes the re-rendered tile to
# any open dashboard over Turbo Streams.
class RefreshPanelJob < ApplicationJob
  queue_as :default

  # ApplicationPanel#refresh! already swallows integration failures into the
  # panel's error state, so a retry here would only help against genuinely
  # unexpected crashes.
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  discard_on ActiveRecord::RecordNotFound

  def perform(panel_id)
    panel = Panel.find(panel_id)
    return unless panel.enabled?

    panel.presenter.refresh!
    broadcast(panel)
  end

  private

  def broadcast(panel)
    Turbo::StreamsChannel.broadcast_replace_to(
      [panel.user, :dashboard],
      target: panel.to_stream_target,
      partial: 'panels/panel',
      locals: { panel: panel }
    )
  end
end

# frozen_string_literal: true

module Api
  module V1
    # One call that returns everything a client needs to draw the whole board.
    class DashboardsController < BaseController
      def show
        # Same additive install the web dashboard does, so a native client and
        # the web app never disagree about which panels exist.
        Dashboards::InstallDefaults.new(current_user).call

        panels = current_user.panels.enabled.ordered
        panels.select(&:stale?).each(&:refresh_later)

        render json: {
          user: {
            id: current_user.id,
            name: current_user.display_name,
            time_zone: current_user.time_zone
          },
          generated_at: Time.current.iso8601,
          panels: panels.map { |panel| PanelSerializer.new(panel).as_json }
        }
      end
    end
  end
end

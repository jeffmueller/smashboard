# frozen_string_literal: true

class DashboardController < ApplicationController
  def show
    # Additive: picks up panel kinds that shipped after this user signed up.
    Dashboards::InstallDefaults.new(current_user).call

    @panels = current_user.panels.enabled.ordered
    @hidden = current_user.panels.where(enabled: false).ordered

    # Anything stale gets refreshed in the background; the page renders
    # immediately from cache and the tile swaps itself in over Turbo when the
    # fetch lands.
    @panels.select(&:stale?).each(&:refresh_later)
  end
end

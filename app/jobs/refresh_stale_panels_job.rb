# frozen_string_literal: true

# Sweeps every enabled remote panel and enqueues a refresh for the ones whose
# cached data has aged past their panel class's interval. Driven by
# config/recurring.yml.
class RefreshStalePanelsJob < ApplicationJob
  queue_as :default

  def perform
    Panel.enabled.find_each do |panel|
      next unless panel.stale?

      RefreshPanelJob.perform_later(panel.id)
    end
  end
end

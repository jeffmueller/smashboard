# frozen_string_literal: true

# Keeps the dedupe ledger from growing without bound. Anything older than the
# retention window can no longer suppress a duplicate worth suppressing.
class PruneNotificationDeliveriesJob < ApplicationJob
  queue_as :default

  def perform
    NotificationDelivery.stale.delete_all
  end
end

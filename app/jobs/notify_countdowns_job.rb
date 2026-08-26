# frozen_string_literal: true

# Fires when a countdown reaches its moment — or ahead of it, if the user set a
# lead time.
#
# The occurrence window starts slightly in the past so a countdown that came due
# between two runs still notifies, rather than being skipped for having already
# passed by the time anyone looked.
class NotifyCountdownsJob < ApplicationJob
  GRACE = 2.minutes

  queue_as :default

  def perform
    Countdown.enabled.includes(:user).find_each do |countdown|
      notify_for(countdown)
    rescue StandardError => e
      Rails.logger.warn("[countdown-reminders] countdown #{countdown.id} failed: #{e.class}: #{e.message}")
    end
  end

  private

  def notify_for(countdown)
    preference = NotificationPreference.resolve(countdown.user, 'countdown_reached')
    return unless preference.enabled?

    lead = preference.setting('lead_minutes').to_i.clamp(0, 1440)
    now = Time.current
    occurrence = countdown.upcoming_occurrences(from: now - GRACE, limit: 1).first
    return if occurrence.blank? || occurrence > now + lead.minutes

    deliver(countdown, occurrence, now)
  end

  def deliver(countdown, occurrence, now)
    minutes = ((occurrence - now) / 60).round

    Notifications::Deliver.call(
      countdown.user,
      'countdown_reached',
      Notifications::Deliver::Payload.new(
        title: countdown.name,
        body: minutes <= 0 ? 'Now' : "in #{minutes} #{'minute'.pluralize(minutes)}",
        url: '/',
        tag: "countdown-#{countdown.id}"
      ),
      dedupe_key: "#{countdown.id}:#{occurrence.to_i}"
    )
  end
end

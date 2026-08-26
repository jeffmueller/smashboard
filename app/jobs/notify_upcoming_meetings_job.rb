# frozen_string_literal: true

# Fires a reminder ahead of each meeting, at whatever lead time the user set.
#
# Reads the calendar panel's cached events rather than calling any calendar API,
# so running this every minute costs one query and no third-party traffic. The
# cache already spans the whole day, so a minute-by-minute scan sees every
# meeting well before it starts.
class NotifyUpcomingMeetingsJob < ApplicationJob
  queue_as :default

  def perform
    Panel.enabled.where(kind: 'calendar').includes(:user).find_each do |panel|
      remind_for(panel)
    rescue StandardError => e
      Rails.logger.warn("[meeting-reminders] panel #{panel.id} failed: #{e.class}: #{e.message}")
    end
  end

  private

  def remind_for(panel)
    preference = NotificationPreference.resolve(panel.user, 'meeting_reminder')
    return unless preference.enabled?

    lead = preference.setting('lead_minutes').to_i.clamp(0, 1440)
    now = Time.current
    cutoff = now + lead.minutes

    Array(panel.data['events']).each do |event|
      next if event['all_day']

      starts_at = parse(event['starts_at'])
      # Already under way, or still further out than the lead time.
      next if starts_at.nil? || starts_at <= now || starts_at > cutoff

      deliver(panel.user, event, starts_at, now)
    end
  end

  def deliver(user, event, starts_at, now)
    minutes = ((starts_at - now) / 60).round

    Notifications::Deliver.call(
      user,
      'meeting_reminder',
      Notifications::Deliver::Payload.new(
        title: event['title'].presence || 'Meeting',
        body: body_for(event, minutes),
        # Tapping the notification opens the call when there is one.
        url: event['video_url'].presence || '/',
        tag: "meeting-#{event['uid']}"
      ),
      dedupe_key: event['uid'].to_s
    )
  end

  def body_for(event, minutes)
    when_text = minutes <= 1 ? 'starting now' : "in #{minutes} minutes"
    join_text = event['video_provider'].present? ? " · tap to join #{event['video_provider']}" : ''

    "#{when_text}#{join_text}"
  end

  def parse(value)
    Time.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end
end

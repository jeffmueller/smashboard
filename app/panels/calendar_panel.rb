# frozen_string_literal: true

# Today's meetings across every connected calendar, with a join link when the
# event carries a video call.
#
# Payload contract:
#   { events: [{ uid:, title:, starts_at:, ends_at:, all_day:, location:,
#                calendar:, organizer:, video_url:, video_provider:,
#                time_label:, in_progress: }],
#     finished_count:, calendar_count:, partial: }
class CalendarPanel < ApplicationPanel
  CLIENTS = {
    'caldav' => Integrations::Caldav,
    'google_calendar' => Integrations::GoogleCalendar
  }.freeze

  class << self
    def title = 'Meetings'
    def description = "Today's meetings, with video call links"
    def required_providers = CLIENTS.keys
    def refresh_interval = 5.minutes
    def default_col_span = 2
  end

  def fetch
    window = day_window
    events, partial = across_connections do |connection|
      client = CLIENTS.fetch(connection.provider)
      client.new(connection).events(from: window.first, to: window.last)
    end

    build_payload(events.flatten, window, partial: partial)
  end

  private

  # "Today" is the user's day, not the server's. The window runs to end of day
  # so an event starting at 11:45pm still counts.
  def day_window
    now = Time.current.in_time_zone(zone)
    [now.beginning_of_day.utc, now.end_of_day.utc]
  end

  def build_payload(events, window, partial:)
    now = Time.current
    today = events.select { |event| within?(event, window) }
    deduped = deduplicate(today).sort_by { |event| [event[:all_day] ? 0 : 1, event[:starts_at]] }

    finished, live = deduped.partition { |event| finished?(event, now) }

    {
      events: (show_finished? ? deduped : live).map { |event| serialize(event, now) },
      finished_count: finished.size,
      calendar_count: connections.size,
      partial: partial,
      window_date: window.first.in_time_zone(zone).to_date.iso8601
    }
  end

  # A calendar server's idea of the window is not the user's day. RFC 4791 has
  # a CalDAV server match a floating all-day date against the range *in UTC*, so
  # a query for an Eastern user's Tuesday also matches Wednesday's all-day
  # events — and nothing downstream would drop them, because an all-day event is
  # never "finished". Keep only what actually overlaps the day we asked for.
  #
  # Half-open at the start, so an event ending exactly at midnight belongs to the
  # day it ended rather than the one beginning then. An event with no DTEND is a
  # point in time (see #time_label), and an interval test would drop it.
  def within?(event, window)
    from, to = window
    return event[:starts_at].between?(from, to) if event[:ends_at] <= event[:starts_at]

    event[:starts_at] <= to && event[:ends_at] > from
  end

  # The same meeting can arrive from two connected accounts (a shared work
  # calendar subscribed in both Fastmail and Google). Same title at the same
  # minute is the same meeting.
  def deduplicate(events)
    events.uniq { |event| [event[:title].to_s.downcase, event[:starts_at].to_i] }
  end

  def finished?(event, now)
    !event[:all_day] && event[:ends_at] <= now
  end

  def show_finished?
    ActiveModel::Type::Boolean.new.cast(settings.fetch('show_finished', false))
  end

  def serialize(event, now)
    {
      uid: event[:uid],
      title: event[:title],
      starts_at: event[:starts_at].iso8601,
      ends_at: event[:ends_at].iso8601,
      all_day: event[:all_day],
      location: event[:location],
      calendar: event[:calendar],
      organizer: event[:organizer],
      video_url: event[:video_url],
      video_provider: event[:video_provider],
      time_label: time_label(event),
      in_progress: !event[:all_day] && event[:starts_at] <= now && event[:ends_at] > now,
      finished: finished?(event, now)
    }
  end

  def time_label(event)
    return 'All day' if event[:all_day]

    starts = event[:starts_at].in_time_zone(zone)
    ends = event[:ends_at].in_time_zone(zone)
    return starts.strftime('%-I:%M %p') if ends <= starts

    "#{starts.strftime('%-I:%M')}–#{ends.strftime('%-I:%M %p')}"
  end
end

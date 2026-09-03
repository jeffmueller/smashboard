# frozen_string_literal: true

module Integrations
  # Google Calendar via the v3 API rather than Google's CalDAV endpoint.
  #
  # The API is the better source here: `singleEvents=true` expands recurrences
  # server-side including moved instances, and conferenceData gives a structured
  # Meet link instead of a URL to be dug out of a description.
  #
  # Auth is a stored refresh token per connection; the OAuth client itself is
  # app-wide and comes from ENV.
  class GoogleCalendar < Base
    include GoogleToken

    # Trailing slash matters: Faraday resolves a leading-slash path as an
    # absolute one, which would silently drop /calendar/v3 from every call.
    BASE_URL = 'https://www.googleapis.com/calendar/v3/'
    CALENDAR_LIST_TTL = 6.hours
    MAX_RESULTS = 50

    def events(from:, to:)
      calendars.flat_map { |calendar| list_events(calendar, from, to) }
    end

    def calendars
      configured = calendar_ids
      return configured.map { |id| { id: id, name: id } } if configured.any?

      Rails.cache.fetch(cache_key('calendars'), expires_in: CALENDAR_LIST_TTL) { fetch_calendar_list }
    end

    private

    def calendar_ids
      raw = setting('calendar_ids')
      list = raw.is_a?(String) ? raw.split(',') : Array(raw)
      list.map(&:strip).compact_blank
    end

    def fetch_calendar_list
      body = request { authorized_get('users/me/calendarList') }

      Array(body['items'])
        .reject { |item| item['deleted'] }
        .reject { |item| item['selected'] == false }
        .map { |item| { id: item['id'], name: item['summaryOverride'].presence || item['summary'] } }
    end

    def list_events(calendar, from, to)
      body = request do
        authorized_get("calendars/#{CGI.escape(calendar[:id])}/events",
                       timeMin: from.utc.iso8601,
                       timeMax: to.utc.iso8601,
                       singleEvents: true,
                       orderBy: 'startTime',
                       maxResults: MAX_RESULTS)
      end

      Array(body['items']).filter_map { |item| normalize(item, calendar[:name]) }
    end

    def normalize(item, calendar_name)
      return nil if item['status'] == 'cancelled'
      return nil if declined?(item)

      all_day = item.dig('start', 'date').present?
      starts_at = parse_boundary(item['start'])
      return nil if starts_at.nil?

      video = video_link(item)

      {
        uid: item['id'],
        title: item['summary'].presence || '(no title)',
        starts_at: starts_at,
        ends_at: parse_boundary(item['end']) || (all_day ? starts_at + 1.day : starts_at),
        all_day: all_day,
        location: location_without_url(item['location'], video),
        description: item['description'].presence,
        calendar: calendar_name,
        organizer: item.dig('organizer', 'displayName').presence || item.dig('organizer', 'email'),
        video_url: video&.url,
        video_provider: video&.provider,
        rrule: nil,
        exdates: []
      }
    end

    # conferenceData is authoritative; hangoutLink is the older field; only then
    # fall back to scraping the free-text fields.
    def video_link(item)
      entry = Array(item.dig('conferenceData', 'entryPoints'))
              .find { |point| point['entryPointType'] == 'video' }

      Meetings::VideoLink.extract(entry&.dig('uri'), item['hangoutLink'], item['location'], item['description'])
    end

    def declined?(item)
      Array(item['attendees']).any? { |attendee| attendee['self'] && attendee['responseStatus'] == 'declined' }
    end

    def parse_boundary(boundary)
      return nil if boundary.blank?

      if boundary['date'].present?
        # A date-only boundary is floating: Google is saying "the 26th", not an
        # instant. Pinned to UTC it becomes 8pm on the 25th for an Eastern user,
        # which lands tomorrow's all-day event on today's dashboard.
        Date.parse(boundary['date']).in_time_zone(zone).utc
      else
        Time.parse(boundary['dateTime']).utc
      end
    rescue ArgumentError, TypeError
      nil
    end

    def location_without_url(location, video)
      text = location.to_s.strip
      return nil if text.blank?
      return nil if video && text.include?(video.url)
      return nil if text.match?(%r{\Ahttps?://\S+\z})

      text
    end

    # --- Auth ---------------------------------------------------------------

    def authorized_get(path, params = {})
      http(BASE_URL).get(path, params) do |request|
        request.headers['Authorization'] = "Bearer #{access_token}"
      end
    end

    def cache_key(suffix)
      "google_calendar/#{connection.id}/#{suffix}"
    end
  end
end

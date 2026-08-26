# frozen_string_literal: true

module Meetings
  # Turns raw iCalendar text into normalised event hashes.
  #
  # Deliberately does no recurrence expansion — a CalDAV server asked to
  # `expand` returns one VEVENT per occurrence already, and only the fallback
  # path needs RecurrenceExpander. Events keep their RRULE/EXDATE so that
  # decision belongs to the caller.
  class IcsParser
    # Events the user has said no to, or that were called off, shouldn't take up
    # room on a dashboard.
    SKIPPED_STATUSES = %w[CANCELLED].freeze

    # Where Google and Outlook stash the join URL when a calendar is read as an
    # ICS feed rather than through their own API. The icalendar gem underscores
    # custom property names, so these are the on-the-wire X- names with the
    # hyphens swapped — `custom_property('x-google-conference')` finds nothing.
    CONFERENCE_PROPERTIES = %w[
      x_google_conference
      x_microsoft_skypeteamsmeetingurl
      x_microsoft_onlinemeetingexternallink
      x_microsoft_onlinemeetingconflink
    ].freeze

    def self.parse(...)
      new(...).call
    end

    def initialize(ics, calendar_name:, user_email: nil)
      @ics = ics
      @calendar_name = calendar_name
      @user_email = user_email.to_s.downcase.presence
    end

    def call
      calendars = Icalendar::Calendar.parse(@ics)
      calendars.flat_map(&:events).filter_map { |event| normalize(event) }
    rescue StandardError => e
      # One malformed event shouldn't cost the user their whole calendar panel.
      Rails.logger.warn("[ics] unparseable calendar data for #{@calendar_name}: #{e.class}: #{e.message}")
      []
    end

    private

    def normalize(event)
      return nil if SKIPPED_STATUSES.include?(event.status.to_s.upcase)
      return nil if declined?(event)

      all_day = event.dtstart.is_a?(Icalendar::Values::Date)
      starts_at = to_time(event.dtstart)
      return nil if starts_at.nil?

      video = VideoLink.extract(
        conference_property(event),
        event.location,
        event.url,
        event.description
      )

      {
        uid: event.uid.to_s.presence || Digest::SHA256.hexdigest("#{event.summary}#{starts_at}"),
        title: event.summary.to_s.presence || '(no title)',
        starts_at: starts_at,
        ends_at: to_time(event.dtend) || default_end(starts_at, all_day),
        all_day: all_day,
        location: presence_without_url(event.location, video),
        description: event.description.to_s.presence,
        calendar: @calendar_name,
        organizer: organizer_of(event),
        video_url: video&.url,
        video_provider: video&.provider,
        rrule: event.rrule.first&.value_ical,
        exdates: Array(event.exdate).flatten.filter_map { |d| to_time(d) }
      }
    end

    # DTEND is optional. A timed event without one is treated as instantaneous
    # per RFC 5545; an all-day one covers its whole day.
    def default_end(starts_at, all_day)
      all_day ? starts_at + 1.day : starts_at
    end

    def to_time(value)
      return nil if value.blank?

      case value
      when Icalendar::Values::Date then value.value.in_time_zone('UTC')
      else value.to_time.utc
      end
    rescue StandardError
      nil
    end

    def conference_property(event)
      return nil unless event.respond_to?(:custom_properties)

      CONFERENCE_PROPERTIES.filter_map { |name| Array(event.custom_properties[name]).first }.first
    end

    def declined?(event)
      return false if @user_email.nil?

      Array(event.attendee).any? do |attendee|
        address(attendee) == @user_email &&
          attendee.ical_params['partstat'].to_a.first.to_s.casecmp('DECLINED').zero?
      end
    end

    def organizer_of(event)
      return nil if event.organizer.blank?

      event.organizer.ical_params['cn'].to_a.first.presence || address(event.organizer)
    end

    def address(value)
      value.to_s.sub(/\Amailto:/i, '').downcase
    end

    # If the location is only the video URL, the link button already says it —
    # repeating the raw URL as location text is noise.
    def presence_without_url(location, video)
      text = location.to_s.strip
      return nil if text.blank?
      return nil if video && text.include?(video.url)
      return nil if text.match?(%r{\Ahttps?://\S+\z})

      text
    end
  end
end

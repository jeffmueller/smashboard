# frozen_string_literal: true

module Meetings
  # Expands recurring events client-side, for CalDAV servers that reject the
  # `expand` form of a calendar-query.
  #
  # This is the fallback, not the main path: a server that expands for us also
  # applies RECURRENCE-ID overrides (a single moved occurrence), which this
  # cannot see because those arrive as separate VEVENTs keyed by the same UID.
  # EXDATE cancellations are honoured.
  class RecurrenceExpander
    MAX_OCCURRENCES = 100

    def self.expand(...)
      new(...).call
    end

    def initialize(events, from:, to:)
      @events = events
      @from = from
      @to = to
    end

    def call
      @events.flat_map { |event| event[:rrule].present? ? occurrences_of(event) : [event] }
             .select { |event| overlaps_window?(event) }
    end

    private

    def occurrences_of(event)
      schedule = schedule_for(event)
      return [event] if schedule.nil?

      duration = event[:ends_at] - event[:starts_at]

      schedule.occurrences_between(@from, @to).first(MAX_OCCURRENCES).map do |occurrence|
        starts_at = occurrence.to_time.utc
        event.merge(
          uid: "#{event[:uid]}##{starts_at.to_i}",
          starts_at: starts_at,
          ends_at: starts_at + duration
        )
      end
    rescue StandardError => e
      Rails.logger.warn("[ics] could not expand #{event[:uid]}: #{e.class}: #{e.message}")
      [event]
    end

    def schedule_for(event)
      IceCube::Schedule.new(event[:starts_at]) do |s|
        s.add_recurrence_rule(IceCube::Rule.from_ical(event[:rrule]))
        event[:exdates].each { |date| s.add_exception_time(date) }
      end
    rescue StandardError
      nil
    end

    def overlaps_window?(event)
      event[:ends_at] > @from && event[:starts_at] < @to
    end
  end
end

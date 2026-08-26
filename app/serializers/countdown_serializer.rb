# frozen_string_literal: true

class CountdownSerializer
  def initialize(countdown, now: Time.current)
    @countdown = countdown
    @now = now
  end

  def as_json(*)
    occurrence_at = @countdown.next_occurrence_at(from: @now)

    {
      id: @countdown.id,
      name: @countdown.name,
      description: @countdown.description,
      color: @countdown.color,
      enabled: @countdown.enabled,
      position: @countdown.position,
      recurring: @countdown.recurring?,
      rrule: @countdown.rrule,
      target_at: @countdown.target_at&.iso8601,
      starts_on: @countdown.starts_on&.iso8601,
      occurs_at_time: @countdown.occurs_at_time&.strftime('%H:%M'),
      time_zone: @countdown.time_zone.presence || @countdown.user.time_zone,
      occurrence_at: occurrence_at&.iso8601,
      seconds_remaining: occurrence_at && (occurrence_at - @now).round,
      returns_after_dismissal: @countdown.recurring?
    }
  end
end

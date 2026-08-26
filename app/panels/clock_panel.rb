# frozen_string_literal: true

# Date and time in the user's zone. The server renders the initial value and
# hands the browser an ISO timestamp plus the zone; a Stimulus controller ticks
# it forward locally so this panel never needs refreshing.
class ClockPanel < ApplicationPanel
  class << self
    def title = 'Clock'
    def description = 'Current date and time'
    def default_col_span = 1
  end

  def build
    now = Time.current.in_time_zone(zone)

    {
      iso: now.iso8601,
      time_zone: zone.name,
      time_zone_abbreviation: now.strftime('%Z'),
      date: now.strftime('%A, %B %-d, %Y'),
      time: now.strftime('%-I:%M %p')
    }
  end
end

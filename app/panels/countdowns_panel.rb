# frozen_string_literal: true

# Live countdowns, soonest first. Each entry carries the absolute occurrence
# timestamp so the browser can tick without polling, and the occurrence key the
# dismiss action needs.
class CountdownsPanel < ApplicationPanel
  class << self
    def title = 'Countdowns'
    def description = 'Time remaining until whatever matters next'
    def default_col_span = 2
  end

  def build
    now = Time.current
    entries = user.countdowns.enabled.ordered.filter_map { |countdown| entry_for(countdown, now) }

    { countdowns: entries.sort_by { |entry| entry[:occurrence_at] } }
  end

  private

  def entry_for(countdown, now)
    occurrence_at = countdown.next_occurrence_at(from: now)
    return nil if occurrence_at.blank?

    {
      id: countdown.id,
      name: countdown.name,
      description: countdown.description,
      color: countdown.color,
      recurring: countdown.recurring?,
      occurrence_at: occurrence_at.iso8601,
      seconds_remaining: (occurrence_at - now).round,
      # Only recurring countdowns come back after a dismissal, so the UI warns
      # before dismissing a one-off.
      dismissable: true,
      returns_after_dismissal: countdown.recurring?
    }
  end
end

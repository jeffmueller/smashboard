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
    return nil if waiting_for_its_day?(countdown, occurrence_at, now)

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

  # A recurring countdown is a thing that happens *today*. The kids come home
  # from school every weekday, and a tile spending this evening counting down 23
  # hours to tomorrow's run tells today's board nothing — so it waits, and
  # reappears at midnight when it becomes today's.
  #
  # One-off countdowns are the opposite: watching a concert in November approach
  # is the entire point, so they are never held back.
  #
  # Display only. The countdown still exists, still notifies on its own lead
  # time, and is still listed at /countdowns.
  def waiting_for_its_day?(countdown, occurrence_at, now)
    countdown.recurring? && countdown.occurs_after_today?(occurrence_at, from: now)
  end
end

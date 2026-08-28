# frozen_string_literal: true

# An arbitrary countdown to a moment in the future.
#
# Two shapes share this model:
#   * one-off  — `target_at` set, `rrule` blank (a concert in November)
#   * recurring — `rrule` + `occurs_at_time` set (kids home from school, weekdays)
#
# A recurring countdown can be waved off for a single iteration: a
# CountdownDismissal pins the exact occurrence being skipped, so the schedule
# rolls straight on to the next one without any other state changing.
class Countdown < ApplicationRecord
  COLORS = %w[sky emerald amber rose violet slate].freeze

  # How far ahead to walk the schedule looking for an undismissed occurrence.
  # Bounds the search when someone dismisses a long run of iterations.
  OCCURRENCE_LOOKAHEAD = 60

  # Used when a recurring countdown has no time of day set.
  DEFAULT_HOUR = 9

  belongs_to :user
  has_many :dismissals, class_name: 'CountdownDismissal', dependent: :destroy

  validates :name, presence: true, length: { maximum: 120 }
  validates :color, inclusion: { in: COLORS }
  validate :schedule_is_defined
  validate :rrule_is_parseable

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:position, :id) }

  def recurring?
    rrule.present?
  end

  def zone
    ActiveSupport::TimeZone[time_zone.presence.to_s] || user.zone
  end

  # The soonest occurrence that hasn't been dismissed, or nil when a one-off has
  # already passed and when a recurring schedule has no live iteration ahead.
  def next_occurrence_at(from: Time.current)
    upcoming_occurrences(from: from).first
  end

  def upcoming_occurrences(from: Time.current, limit: 1)
    dismissed = dismissed_occurrence_keys
    candidate_occurrences(from).lazy.reject { |at| dismissed.include?(occurrence_key(at)) }.first(limit)
  end

  # Whether an occurrence lands on a later calendar day than `from`, judged in
  # this countdown's own zone — the zone its schedule runs in, and so the one
  # whose midnight decides when "tomorrow" becomes "today".
  def occurs_after_today?(occurrence_at, from: Time.current)
    return false if occurrence_at.blank?

    occurrence_at.in_time_zone(zone).to_date > from.in_time_zone(zone).to_date
  end

  def seconds_remaining(from: Time.current)
    at = next_occurrence_at(from: from)
    return nil if at.blank?

    (at - from).round
  end

  # Wave off one iteration. Recurring countdowns reappear on their next
  # scheduled occurrence; a one-off simply goes quiet for good.
  def dismiss!(occurrence_at)
    dismissals.find_or_create_by!(occurrence_at: normalize(occurrence_at)).tap do
      @dismissed_occurrence_keys = nil
    end
  end

  # Dismissals are cached for the duration of one occurrence walk; reloading the
  # record has to drop that cache or the next lookup answers from stale state.
  def reload(...)
    @dismissed_occurrence_keys = nil
    super
  end

  def dismissed?(occurrence_at)
    dismissed_occurrence_keys.include?(occurrence_key(occurrence_at))
  end

  def schedule
    return nil unless recurring?

    IceCube::Schedule.new(schedule_start).tap do |s|
      s.add_recurrence_rule(IceCube::Rule.from_ical(rrule))
    end
  end

  private

  def candidate_occurrences(from)
    if recurring?
      schedule.next_occurrences(OCCURRENCE_LOOKAHEAD, from).map { |occurrence| normalize(occurrence.to_time) }
    elsif target_at.present? && target_at > from
      [normalize(target_at)]
    else
      []
    end
  end

  # `occurs_at_time` is a `time` column, and Active Record stores it as an
  # instant: the form runs inside the user's zone, so 2:20pm is written as
  # 19:20 UTC. Reading it back therefore has to name a zone, and the only right
  # one is this countdown's own — the same zone the schedule is built in.
  #
  # Reading it in whatever zone happens to be ambient is what the two callers
  # used to do, and they disagreed: a request runs in the user's zone and got
  # 14:20, while the notifier has no ambient zone and got 19:20. Reading it in
  # UTC is wrong in the other direction — it gives every countdown the offset as
  # a shift, which is the +5 hours this replaces.
  def schedule_start
    date = starts_on || created_at&.in_time_zone(zone)&.to_date || zone.today
    at = occurs_at_time&.in_time_zone(zone)
    zone.local(date.year, date.month, date.day, at&.hour || DEFAULT_HOUR, at&.min || 0, 0)
  end

  # Dismissals are matched to the second in UTC. Comparing Time objects
  # directly would be at the mercy of sub-second drift between IceCube's
  # generated occurrences and what Postgres round-trips.
  def occurrence_key(time)
    time.to_i
  end

  def normalize(time)
    time.utc.change(usec: 0)
  end

  def dismissed_occurrence_keys
    @dismissed_occurrence_keys ||= dismissals.pluck(:occurrence_at).to_set { |at| occurrence_key(at) }
  end

  def schedule_is_defined
    return if recurring? || target_at.present?

    errors.add(:base, 'needs either a target date or a recurrence rule')
  end

  def rrule_is_parseable
    return if rrule.blank?

    IceCube::Rule.from_ical(rrule)
  rescue StandardError
    errors.add(:rrule, 'is not a valid iCalendar recurrence rule')
  end
end

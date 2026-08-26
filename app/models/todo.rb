# frozen_string_literal: true

# Todos are first-class here rather than synced from OmniFocus, which has no
# public API. Deferral and RRULE repetition mirror the OmniFocus concepts worth
# keeping; the recurrence engine is shared with Countdown.
class Todo < ApplicationRecord
  belongs_to :user
  belongs_to :todo_project, optional: true

  validates :title, presence: true, length: { maximum: 500 }
  validate :rrule_is_parseable

  scope :incomplete, -> { where(completed_at: nil) }
  scope :complete, -> { where.not(completed_at: nil) }
  scope :ordered, -> { order(:position, :id) }
  scope :flagged, -> { where(flagged: true) }

  # Not yet deferred into the future — i.e. actionable now.
  scope :available, ->(at = Time.current) { where(defer_until: nil).or(where(defer_until: ..at)) }

  scope :due_before, ->(at) { where(due_at: ..at) }
  scope :overdue, ->(at = Time.current) { incomplete.where(due_at: ...at) }

  # Everything a user should look at today: due by end of their day, plus
  # anything flagged, minus what's still deferred.
  scope :for_today, lambda { |user, now: Time.current|
    end_of_day = user.zone.now.end_of_day
    incomplete.available(now)
              .where(user: user)
              .where(id: due_before(end_of_day).select(:id))
              .or(incomplete.available(now).where(user: user).where(id: flagged.select(:id)))
  }

  def completed?
    completed_at.present?
  end

  def overdue?(at: Time.current)
    !completed? && due_at.present? && due_at < at
  end

  def repeating?
    rrule.present?
  end

  # Completing a repeating todo closes this instance and schedules the next one,
  # so a daily task never silently disappears.
  def complete!(at: Time.current)
    transaction do
      update!(completed_at: at)
      spawn_next_occurrence(at) if repeating?
    end
  end

  def uncomplete!
    update!(completed_at: nil)
  end

  def next_due_at(after: Time.current)
    return nil unless repeating? && due_at.present?

    schedule.next_occurrence(after)&.to_time
  end

  def schedule
    return nil unless repeating? && due_at.present?

    IceCube::Schedule.new(due_at.in_time_zone(user.zone)).tap do |s|
      s.add_recurrence_rule(IceCube::Rule.from_ical(rrule))
    end
  end

  private

  def spawn_next_occurrence(at)
    next_due = next_due_at(after: at)
    return if next_due.blank?

    user.todos.create!(
      todo_project: todo_project,
      title: title,
      notes: notes,
      due_at: next_due,
      defer_until: defer_until.present? ? next_due - (due_at - defer_until) : nil,
      flagged: flagged,
      rrule: rrule,
      position: position
    )
  end

  def rrule_is_parseable
    return if rrule.blank?

    IceCube::Rule.from_ical(rrule)
  rescue StandardError
    errors.add(:rrule, 'is not a valid iCalendar recurrence rule')
  end
end

# frozen_string_literal: true

# Something you mean to do every day. Local data — no integration.
#
# Not completing a habit records nothing: absence is the miss. That keeps the
# table proportional to what actually happened rather than to days elapsed, and
# means adding a habit doesn't retroactively invent a history of failures.
class Habit < ApplicationRecord
  include Positioned

  belongs_to :user
  has_many :habit_completions, dependent: :destroy

  validates :name, presence: true, length: { maximum: 80 }
  validates :name, uniqueness: { scope: :user_id, case_sensitive: false }
  validates :icon, length: { maximum: 8 }

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  def archived? = archived_at.present?

  def archive! = update!(archived_at: Time.current)

  def unarchive! = update!(archived_at: nil)

  # What to show when there's no emoji: the first letter of the name, which
  # needs no network request and themes correctly.
  def initial
    name.to_s.strip.first.to_s.upcase.presence || '?'
  end

  def completed_on?(date)
    habit_completions.exists?(completed_on: date)
  end

  # Checking off is idempotent on purpose — a double tap on a phone shouldn't
  # be an error, and the unique index would raise on the second insert.
  def complete!(date)
    habit_completions.find_or_create_by!(completed_on: date)
  end

  def uncomplete!(date)
    habit_completions.where(completed_on: date).destroy_all
  end

  # Not `toggle!` — ActiveRecord already defines that for flipping a boolean
  # column, and shadowing it with a different signature is the kind of collision
  # that only surfaces when something inside Rails calls the original.
  def toggle_completion!(date)
    completed_on?(date) ? uncomplete!(date) : complete!(date)
    completed_on?(date)
  end

  # Consecutive days ending today, or ending yesterday when today isn't done
  # yet. A streak that only counted back from today would read zero every
  # morning until you checked in, which is discouraging and inaccurate — the
  # run is still alive until the day is actually missed.
  def streak(today:)
    days = habit_completions.where(completed_on: ..today).order(completed_on: :desc).pluck(:completed_on)
    return 0 if days.empty?

    expected = days.first == today ? today : today - 1
    return 0 if days.first != expected

    days.take_while { |day| (day == expected).tap { expected -= 1 } }.size
  end
end

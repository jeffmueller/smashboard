# frozen_string_literal: true

# Daily habits: what's left today, and how the last quarter has gone.
#
# Payload contract:
#   { today:, habits: [{ id:, name:, icon:, initial:, done:, streak: }],
#     done_count:, total_count:,
#     activity: { start_on:, end_on:, weeks: [[{ date:, in_range:, done_ids:, level: }]] } }
class HabitsPanel < ApplicationPanel
  # Half a year. Whole weeks, so every column is a full column — and enough of
  # them that the grid fills a tile at the widths a panel actually gets rather
  # than sitting in one corner of it.
  ACTIVITY_WEEKS = 26
  # Five steps: nothing, then four intensities. Matching the level count to the
  # ramp in HabitsHelper keeps the two from drifting.
  LEVELS = 4

  class << self
    def title = 'Habits'
    def description = 'Daily habits and how the last quarter has gone'
    def default_col_span = 2
  end

  def build
    today = Time.current.in_time_zone(zone).to_date
    habits = user.habits.active.ordered.to_a
    done = completions_on(habits, today)

    {
      today: today.iso8601,
      habits: habits.map { |habit| serialize(habit, today, done) },
      done_count: done.size,
      total_count: habits.size,
      activity: activity(habits, today)
    }
  end

  private

  def serialize(habit, today, done_today)
    {
      id: habit.id,
      name: habit.name,
      icon: habit.icon.presence,
      initial: habit.initial,
      done: done_today.include?(habit.id),
      streak: habit.streak(today: today)
    }
  end

  def completions_on(habits, date)
    HabitCompletion.where(habit_id: habits.map(&:id), completed_on: date).pluck(:habit_id).to_set
  end

  # The grid runs in whole weeks so each column is a week and each row a
  # weekday. It starts on the Sunday on or before the first day, and the days
  # that fall outside the window are still rendered — as blanks — so the shape
  # stays rectangular instead of ragged at the corners.
  def activity(habits, today)
    last_day = today
    first_day = last_day - ((ACTIVITY_WEEKS * 7) - 1)
    grid_start = first_day.beginning_of_week(:sunday)

    by_date = completions_by_date(habits, grid_start, last_day)
    weeks = (grid_start..last_day.end_of_week(:sunday)).each_slice(7).map do |week|
      week.map { |date| cell(date, first_day, last_day, by_date, habits.size) }
    end

    { start_on: first_day.iso8601, end_on: last_day.iso8601, weeks: weeks }
  end

  def completions_by_date(habits, from, to)
    HabitCompletion.where(habit_id: habits.map(&:id))
                   .between(from, to)
                   .pluck(:completed_on, :habit_id)
                   .group_by(&:first)
                   .transform_values { |rows| rows.map(&:last) }
  end

  def cell(date, first_day, last_day, by_date, habit_count)
    in_range = date.between?(first_day, last_day)
    done_ids = in_range ? Array(by_date[date]) : []

    { date: date.iso8601, in_range: in_range, done_ids: done_ids,
      level: level_for(done_ids.size, habit_count) }
  end

  # Share of the day's habits completed, in four steps. Anything done at all is
  # at least level 1, so a single completion never renders as an empty square.
  def level_for(done, total)
    return 0 if done.zero? || total.zero?

    [(done.to_f / total * LEVELS).ceil, LEVELS].min
  end
end

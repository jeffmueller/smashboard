# frozen_string_literal: true

class HabitSerializer
  def initialize(habit, today: nil)
    @habit = habit
    @today = today || Time.zone.today
  end

  def as_json(*)
    {
      id: @habit.id,
      name: @habit.name,
      icon: @habit.icon.presence,
      initial: @habit.initial,
      position: @habit.position,
      archived: @habit.archived?,
      done_today: @habit.completed_on?(@today),
      streak: @habit.streak(today: @today)
    }
  end
end

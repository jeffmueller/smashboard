# frozen_string_literal: true

# Development seed: one signed-in-able user with a dashboard that demonstrates
# the countdown, todo, habit and clock panels working end to end.
#
#   bin/rails db:seed
#
# Sign in as dev@smashboard.local / password

return unless Rails.env.development?

user = User.find_or_initialize_by(email: 'dev@smashboard.local')
user.assign_attributes(
  first_name: 'Alex',
  last_name: 'Rivera',
  password: 'password',
  password_confirmation: 'password',
  time_zone: 'Eastern Time (US & Canada)',
  postal_code: '10001'
)
user.save!

Dashboards::InstallDefaults.new(user).call

# `occurs_at_time` is a `time` column that Active Record stores as an instant, so
# the zone in force when it is written is the zone it means. The app always
# writes it inside a request, in the user's zone; seeds run in a rake task, where
# the ambient zone is UTC — so say the zone explicitly or 15:10 lands as 11:10
# on the board.
if user.countdowns.none?
  user.countdowns.create!(
    name: 'Kid one home from school',
    description: 'Bus drop-off',
    color: 'emerald',
    rrule: 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR',
    starts_on: Date.current,
    occurs_at_time: user.zone.parse('15:10')
  )

  user.countdowns.create!(
    name: 'Kid two home from school',
    description: 'Walks back with the neighbours',
    color: 'sky',
    rrule: 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR',
    starts_on: Date.current,
    occurs_at_time: user.zone.parse('16:05')
  )

  user.countdowns.create!(
    name: 'Concert',
    description: 'Doors at 7',
    color: 'violet',
    target_at: 6.weeks.from_now.change(hour: 19)
  )
end

if user.todos.none?
  home = user.todo_projects.create!(name: 'Home', color: 'emerald')
  user.todos.create!(title: 'Renew car registration', due_at: 2.days.from_now, todo_project: home)
  user.todos.create!(title: 'Reply to the school email', due_at: Time.current.end_of_day, flagged: true)
  user.todos.create!(title: 'Take the bins out', due_at: Time.current.end_of_day, rrule: 'FREQ=WEEKLY;BYDAY=SU',
                     todo_project: home)
  user.todos.create!(title: 'Book flights', defer_until: 1.week.from_now)
end

if user.habits.none?
  # The habits panel is mostly its activity grid, and an empty grid demonstrates
  # nothing — so the seed lays down the half-year of history the panel actually
  # draws (`HabitsPanel::ACTIVITY_WEEKS`).
  #
  # The rhythms are deterministic rather than random: a reseeded board looks the
  # same twice, the streaks stay explainable, and each habit is a different
  # shape on the graph — an unbroken run, a weekdays-only comb, a lapse that
  # recovered, and one that started recently.
  today = Time.current.in_time_zone(user.zone).to_date
  window = (today - ((HabitsPanel::ACTIVITY_WEEKS * 7) - 1))..today
  lapse = (today - 40)..(today - 27)
  # A week away, when nothing got done at all. Without it the busiest habit
  # covers every day in the window and the grid never renders a level-0 square,
  # which is the one step of the ramp that means "nothing happened".
  away = (today - 130)..(today - 124)

  [
    { name: 'Read', icon: '📖', done: ->(_date) { true } },
    { name: 'Move', icon: '🏃', done: ->(date) { !date.on_weekend? } },
    { name: 'Practice guitar', icon: '🎸', done: ->(date) { !lapse.cover?(date) && (date.yday % 5) != 0 } },
    # Not done today on purpose, so the tile shows a checked row and an
    # unchecked one rather than a uniform column of ticks.
    { name: 'Journal', icon: '📓', done: ->(date) { date >= today - 20 && date != today } }
  ].each_with_index do |seed, index|
    habit = user.habits.create!(name: seed[:name], icon: seed[:icon], position: index)
    rows = window.select { |date| seed[:done].call(date) && !away.cover?(date) }
                 .map { |date| { habit_id: habit.id, completed_on: date } }
    # Six months of history per habit is a bulk backfill of rows that have no
    # callbacks and nothing to validate beyond the unique index already on the
    # table, so it goes in one statement rather than a few hundred.
    HabitCompletion.insert_all(rows) # rubocop:disable Rails/SkipsModelValidations
  end
end

puts "Seeded #{user.email} with #{user.panels.count} panels, #{user.countdowns.count} countdowns, " \
     "#{user.todos.count} todos, #{user.habits.count} habits."

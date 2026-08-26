# frozen_string_literal: true

# Today's list: anything due by the end of the user's day plus anything
# flagged, with deferred items held back until their defer date passes.
class TodosPanel < ApplicationPanel
  DEFAULT_LIMIT = 12

  class << self
    def title = 'Today'
    def description = "Today's todo list"
    def default_col_span = 2
    def default_row_span = 2
  end

  def build
    now = Time.current
    scope = Todo.for_today(user, now: now).includes(:todo_project).ordered.limit(limit)
    todos = scope.map { |todo| serialize(todo, now) }

    {
      todos: todos,
      overdue_count: Todo.where(user: user).overdue(now).count,
      remaining_count: user.todos.incomplete.available(now).count
    }
  end

  private

  def limit
    settings.fetch('limit', DEFAULT_LIMIT).to_i.clamp(1, 50)
  end

  def serialize(todo, now)
    {
      id: todo.id,
      title: todo.title,
      notes: todo.notes,
      flagged: todo.flagged,
      completed: todo.completed?,
      overdue: todo.overdue?(at: now),
      repeating: todo.repeating?,
      due_at: todo.due_at&.iso8601,
      due_label: due_label(todo, now),
      project: todo.todo_project && { id: todo.todo_project.id, name: todo.todo_project.name,
                                      color: todo.todo_project.color }
    }
  end

  def due_label(todo, now)
    return nil if todo.due_at.blank?

    due = todo.due_at.in_time_zone(zone)
    today = now.in_time_zone(zone).to_date

    case due.to_date
    when today then due.strftime('%-I:%M %p')
    when today - 1 then 'Yesterday'
    when today + 1 then "Tomorrow #{due.strftime('%-I:%M %p')}"
    else due.strftime('%b %-d')
    end
  end
end

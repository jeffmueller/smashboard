# frozen_string_literal: true

class TodoSerializer
  def initialize(todo)
    @todo = todo
  end

  def as_json(*)
    {
      id: @todo.id,
      title: @todo.title,
      notes: @todo.notes,
      flagged: @todo.flagged,
      completed: @todo.completed?,
      completed_at: @todo.completed_at&.iso8601,
      overdue: @todo.overdue?,
      repeating: @todo.repeating?,
      rrule: @todo.rrule,
      due_at: @todo.due_at&.iso8601,
      defer_until: @todo.defer_until&.iso8601,
      position: @todo.position,
      project: project_json
    }
  end

  private

  def project_json
    return nil if @todo.todo_project.nil?

    { id: @todo.todo_project.id, name: @todo.todo_project.name, color: @todo.todo_project.color }
  end
end

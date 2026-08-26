# frozen_string_literal: true

class CreateTodos < ActiveRecord::Migration[8.1]
  def change
    create_table :todo_projects do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :color, null: false, default: 'slate'
      t.integer :position, null: false, default: 0
      t.datetime :archived_at

      t.timestamps
    end

    add_index :todo_projects, %i[user_id position]

    create_table :todos do |t|
      t.references :user, null: false, foreign_key: true
      t.references :todo_project, foreign_key: true
      t.string :title, null: false
      t.text :notes
      t.datetime :due_at
      # OmniFocus-style deferral: hidden from "today" until this passes.
      t.datetime :defer_until
      t.datetime :completed_at
      t.boolean :flagged, null: false, default: false
      # Repeating todos reuse the same RRULE engine as recurring countdowns.
      t.string :rrule
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :todos, %i[user_id completed_at]
    add_index :todos, %i[user_id due_at]
    add_index :todos, %i[user_id position]
  end
end

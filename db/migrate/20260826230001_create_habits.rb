# frozen_string_literal: true

class CreateHabits < ActiveRecord::Migration[8.1]
  def change
    create_table :habits do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      # An optional emoji, same as bookmarks — chosen, never fetched.
      t.string :icon
      t.integer :position, null: false, default: 0
      # Retiring a habit keeps its history rather than deleting it, so the
      # activity graph doesn't develop holes in the past.
      t.datetime :archived_at
      t.timestamps
    end
    add_index :habits, %i[user_id position]
    # Backs the case-insensitive uniqueness validation. Without it two
    # concurrent requests can both pass validation and both insert.
    add_index :habits, 'user_id, lower(name)', unique: true, name: 'index_habits_on_user_id_and_lower_name'

    create_table :habit_completions do |t|
      t.references :habit, null: false, foreign_key: true
      # A date, not a timestamp: "done today" is a claim about the user's day in
      # their own zone, and storing an instant would put a completion logged at
      # 11pm Pacific on tomorrow's square.
      t.date :completed_on, null: false
      t.timestamps
    end
    # Checking off twice on the same day is the same fact, and the graph counts
    # rows — so the database refuses the duplicate rather than double-counting.
    add_index :habit_completions, %i[habit_id completed_on], unique: true
  end
end

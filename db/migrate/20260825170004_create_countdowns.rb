# frozen_string_literal: true

class CreateCountdowns < ActiveRecord::Migration[8.1]
  def change
    create_table :countdowns do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :color, null: false, default: 'sky'
      t.integer :position, null: false, default: 0
      t.boolean :enabled, null: false, default: true

      # One-off events (a concert) set target_at and leave rrule null.
      t.datetime :target_at
      # Recurring events (kids home from school) set an RFC 5545 RRULE plus the
      # local time of day each occurrence lands on.
      t.string :rrule
      t.date :starts_on
      t.time :occurs_at_time
      # Falls back to the user's zone when blank.
      t.string :time_zone

      t.timestamps
    end

    add_index :countdowns, %i[user_id position]

    create_table :countdown_dismissals do |t|
      t.references :countdown, null: false, foreign_key: true
      # The exact occurrence that was waved off. Dismissing one iteration never
      # touches the next: the schedule simply skips any occurrence listed here.
      t.datetime :occurrence_at, null: false

      t.timestamps
    end

    add_index :countdown_dismissals, %i[countdown_id occurrence_at], unique: true
  end
end

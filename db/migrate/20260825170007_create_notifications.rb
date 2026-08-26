# frozen_string_literal: true

class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :push_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :endpoint, null: false
      t.string :p256dh_key, null: false
      t.string :auth_key, null: false
      t.string :user_agent
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :push_subscriptions, :endpoint, unique: true

    create_table :notification_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false
      t.boolean :enabled, null: false, default: true
      t.boolean :via_web_push, null: false, default: true
      t.boolean :via_email, null: false, default: false
      # Per-kind tuning: lead time for meetings, severity floor for weather.
      t.jsonb :settings, null: false, default: {}

      t.timestamps
    end

    add_index :notification_preferences, %i[user_id kind], unique: true
  end
end

# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_28_140001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "agent_usage_reports", force: :cascade do |t|
    t.string "agent", null: false
    t.datetime "created_at", null: false
    t.string "machine", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "reported_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "agent", "machine"], name: "index_agent_usage_reports_on_user_id_and_agent_and_machine", unique: true
    t.index ["user_id"], name: "index_agent_usage_reports_on_user_id"
  end

  create_table "api_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.string "name", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
  end

  create_table "bookmarks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "icon"
    t.integer "position", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "position"], name: "index_bookmarks_on_user_id_and_position"
    t.index ["user_id"], name: "index_bookmarks_on_user_id"
  end

  create_table "connections", force: :cascade do |t|
    t.datetime "authorized_at"
    t.datetime "created_at", null: false
    t.text "credentials"
    t.string "label", null: false
    t.text "last_error"
    t.datetime "last_error_at"
    t.datetime "last_synced_at"
    t.string "provider", null: false
    t.jsonb "settings", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "provider", "label"], name: "index_connections_on_user_id_and_provider_and_label", unique: true
    t.index ["user_id", "provider"], name: "index_connections_on_user_id_and_provider"
    t.index ["user_id"], name: "index_connections_on_user_id"
  end

  create_table "countdown_dismissals", force: :cascade do |t|
    t.bigint "countdown_id", null: false
    t.datetime "created_at", null: false
    t.datetime "occurrence_at", null: false
    t.datetime "updated_at", null: false
    t.index ["countdown_id", "occurrence_at"], name: "index_countdown_dismissals_on_countdown_id_and_occurrence_at", unique: true
    t.index ["countdown_id"], name: "index_countdown_dismissals_on_countdown_id"
  end

  create_table "countdowns", force: :cascade do |t|
    t.string "color", default: "sky", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.string "name", null: false
    t.time "occurs_at_time"
    t.integer "position", default: 0, null: false
    t.string "rrule"
    t.date "starts_on"
    t.datetime "target_at"
    t.string "time_zone"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "position"], name: "index_countdowns_on_user_id_and_position"
    t.index ["user_id"], name: "index_countdowns_on_user_id"
  end

  create_table "habit_completions", force: :cascade do |t|
    t.date "completed_on", null: false
    t.datetime "created_at", null: false
    t.bigint "habit_id", null: false
    t.datetime "updated_at", null: false
    t.index ["habit_id", "completed_on"], name: "index_habit_completions_on_habit_id_and_completed_on", unique: true
    t.index ["habit_id"], name: "index_habit_completions_on_habit_id"
  end

  create_table "habits", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.string "icon"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index "user_id, lower((name)::text)", name: "index_habits_on_user_id_and_lower_name", unique: true
    t.index ["user_id", "position"], name: "index_habits_on_user_id_and_position"
    t.index ["user_id"], name: "index_habits_on_user_id"
  end

  create_table "notification_deliveries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "dedupe_key", null: false
    t.datetime "delivered_at", null: false
    t.string "kind", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["delivered_at"], name: "index_notification_deliveries_on_delivered_at"
    t.index ["user_id", "kind", "dedupe_key"], name: "idx_on_user_id_kind_dedupe_key_5e1f6c0f14", unique: true
    t.index ["user_id"], name: "index_notification_deliveries_on_user_id"
  end

  create_table "notification_preferences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.string "kind", null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.boolean "via_email", default: false, null: false
    t.boolean "via_web_push", default: true, null: false
    t.index ["user_id", "kind"], name: "index_notification_preferences_on_user_id_and_kind", unique: true
    t.index ["user_id"], name: "index_notification_preferences_on_user_id"
  end

  create_table "panels", force: :cascade do |t|
    t.integer "col_span", default: 1, null: false
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "data_fetched_at"
    t.string "data_status", default: "idle", null: false
    t.boolean "enabled", default: true, null: false
    t.string "kind", null: false
    t.text "last_error"
    t.integer "position", default: 0, null: false
    t.integer "row_span", default: 1, null: false
    t.jsonb "settings", default: {}, null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "kind"], name: "index_panels_on_user_id_and_kind"
    t.index ["user_id", "position"], name: "index_panels_on_user_id_and_position"
    t.index ["user_id"], name: "index_panels_on_user_id"
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.string "auth_key", null: false
    t.datetime "created_at", null: false
    t.string "endpoint", null: false
    t.datetime "last_used_at"
    t.string "p256dh_key", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "todo_projects", force: :cascade do |t|
    t.datetime "archived_at"
    t.string "color", default: "slate", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "position"], name: "index_todo_projects_on_user_id_and_position"
    t.index ["user_id"], name: "index_todo_projects_on_user_id"
  end

  create_table "todos", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "defer_until"
    t.datetime "due_at"
    t.boolean "flagged", default: false, null: false
    t.text "notes"
    t.integer "position", default: 0, null: false
    t.string "rrule"
    t.string "title", null: false
    t.bigint "todo_project_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["todo_project_id"], name: "index_todos_on_todo_project_id"
    t.index ["user_id", "completed_at"], name: "index_todos_on_user_id_and_completed_at"
    t.index ["user_id", "due_at"], name: "index_todos_on_user_id_and_due_at"
    t.index ["user_id", "position"], name: "index_todos_on_user_id_and_position"
    t.index ["user_id"], name: "index_todos_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "first_name"
    t.string "last_name"
    t.string "postal_code"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "theme"
    t.string "time_zone", default: "UTC", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "agent_usage_reports", "users"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "bookmarks", "users"
  add_foreign_key "connections", "users"
  add_foreign_key "countdown_dismissals", "countdowns"
  add_foreign_key "countdowns", "users"
  add_foreign_key "habit_completions", "habits"
  add_foreign_key "habits", "users"
  add_foreign_key "notification_deliveries", "users"
  add_foreign_key "notification_preferences", "users"
  add_foreign_key "panels", "users"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "todo_projects", "users"
  add_foreign_key "todos", "todo_projects"
  add_foreign_key "todos", "users"
end

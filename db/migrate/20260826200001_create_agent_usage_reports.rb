# frozen_string_literal: true

class CreateAgentUsageReports < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_usage_reports do |t|
      t.references :user, null: false, foreign_key: true
      # Which coding agent, so this can cover more than Claude Code later.
      t.string :agent, null: false
      # The machine that reported. Usage lives where the agent runs, and a user
      # may run one on a laptop and a desktop.
      t.string :machine, null: false
      t.jsonb :payload, null: false, default: {}
      # When the reporter collected it, not when it arrived.
      t.datetime :reported_at, null: false
      t.timestamps
    end

    # One current row per machine per agent: each push replaces the last, so
    # the table stays the size of the user's hardware rather than growing
    # forever with snapshots nothing reads.
    add_index :agent_usage_reports, %i[user_id agent machine], unique: true
  end
end

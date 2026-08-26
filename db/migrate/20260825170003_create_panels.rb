# frozen_string_literal: true

# A Panel is one tile placed on a user's dashboard. `data` caches the last
# successful provider payload so a page render never blocks on a third-party
# API; refresh happens out of band and broadcasts a Turbo Stream.
class CreatePanels < ActiveRecord::Migration[8.1]
  def change
    create_table :panels do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :title
      t.integer :position, null: false, default: 0
      t.integer :col_span, null: false, default: 1
      t.integer :row_span, null: false, default: 1
      t.boolean :enabled, null: false, default: true
      t.jsonb :settings, null: false, default: {}
      t.jsonb :data, null: false, default: {}
      t.datetime :data_fetched_at
      t.string :data_status, null: false, default: 'idle'
      t.text :last_error

      t.timestamps
    end

    add_index :panels, %i[user_id position]
    add_index :panels, %i[user_id kind]
  end
end

# frozen_string_literal: true

# A Connection is one linked external account. A user may hold several per
# provider (two Slack workspaces, three IMAP mailboxes), which is why the
# unique index is on (user_id, provider, label) rather than (user_id, provider).
class CreateConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :connections do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :label, null: false
      # Encrypted at rest via ActiveRecord::Encryption; holds app passwords,
      # OAuth refresh tokens and API keys, so it never leaves this column.
      t.text :credentials
      t.jsonb :settings, null: false, default: {}
      t.string :status, null: false, default: 'pending'
      t.datetime :last_synced_at
      t.datetime :last_error_at
      t.text :last_error

      t.timestamps
    end

    add_index :connections, %i[user_id provider]
    add_index :connections, %i[user_id provider label], unique: true
  end
end

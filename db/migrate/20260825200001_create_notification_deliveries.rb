# frozen_string_literal: true

# Records that a given notification already went out, so a job that scans every
# minute can be safely re-run without notifying twice for the same meeting,
# headline or countdown. The unique index is the actual guard — two workers
# racing on the same reminder is a real possibility, so the check is a write,
# not a read.
class CreateNotificationDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :notification_deliveries do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :dedupe_key, null: false
      t.datetime :delivered_at, null: false

      t.timestamps
    end

    add_index :notification_deliveries, %i[user_id kind dedupe_key], unique: true
    add_index :notification_deliveries, :delivered_at
  end
end

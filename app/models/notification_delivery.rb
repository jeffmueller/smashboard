# frozen_string_literal: true

class NotificationDelivery < ApplicationRecord
  # Long enough that a daily reminder can't repeat, short enough that the table
  # stays small. Pruned by a recurring job.
  RETENTION = 30.days

  belongs_to :user

  validates :kind, :dedupe_key, :delivered_at, presence: true

  scope :stale, -> { where(delivered_at: ...RETENTION.ago) }

  # Returns true when this is the first time; false when it already went out.
  # Relies on the unique index rather than a read-then-write, so two workers
  # racing produce exactly one notification.
  def self.claim(user:, kind:, dedupe_key:)
    create!(user: user, kind: kind, dedupe_key: dedupe_key, delivered_at: Time.current)
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end
end

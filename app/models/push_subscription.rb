# frozen_string_literal: true

# A browser's Web Push endpoint, registered by the PWA service worker.
class PushSubscription < ApplicationRecord
  belongs_to :user

  validates :endpoint, presence: true, uniqueness: true
  validates :p256dh_key, :auth_key, presence: true

  def to_web_push
    {
      endpoint: endpoint,
      keys: { p256dh: p256dh_key, auth: auth_key }
    }
  end
end

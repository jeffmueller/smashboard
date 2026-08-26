# frozen_string_literal: true

module Notifications
  # Sends one notification to a user across whichever channels they've enabled
  # for that kind.
  #
  # Pass a dedupe_key for anything a recurring job might produce more than once
  # (a meeting reminder, a breaking headline). The key is claimed through a
  # unique index before anything is sent, so a re-run — or two workers racing —
  # yields exactly one notification.
  #
  # A dead push endpoint (browser uninstalled, subscription expired) prunes
  # itself rather than failing the send.
  class Deliver
    Payload = Struct.new(:title, :body, :url, :tag, :require_interaction, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(user, kind, payload, dedupe_key: nil)
      @user = user
      @kind = kind
      @payload = payload
      @dedupe_key = dedupe_key
    end

    def call
      preference = NotificationPreference.resolve(@user, @kind)
      return false unless preference.enabled?
      return false unless channels_available?(preference)
      return false unless claim

      deliver_web_push if preference.via_web_push?
      true
    end

    private

    # Claiming before delivery means a crash mid-send loses a notification
    # rather than repeating it every minute until it succeeds.
    def claim
      return true if @dedupe_key.blank?

      NotificationDelivery.claim(user: @user, kind: @kind, dedupe_key: @dedupe_key)
    end

    def channels_available?(preference)
      preference.deliver_via.any?
    end

    def deliver_web_push
      if vapid_keys.values.any?(&:blank?)
        Rails.logger.warn('[push] VAPID keys are not configured; skipping delivery')
        return
      end

      @user.push_subscriptions.find_each { |subscription| send_to(subscription) }
    end

    def send_to(subscription)
      WebPush.payload_send(
        message: message_json,
        endpoint: subscription.endpoint,
        p256dh: subscription.p256dh_key,
        auth: subscription.auth_key,
        vapid: vapid_keys
      )
      # Bookkeeping only — a failure to stamp this must not fail the send.
      subscription.update_column(:last_used_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
      subscription.destroy
    rescue WebPush::ResponseError, WebPush::Unauthorized => e
      Rails.logger.warn("[push] delivery failed for subscription #{subscription.id}: #{e.message}")
    end

    def message_json
      {
        title: @payload.title,
        body: @payload.body,
        url: @payload.url,
        tag: @payload.tag,
        require_interaction: @payload.require_interaction
      }.compact.to_json
    end

    def vapid_keys
      @vapid_keys ||= {
        subject: ENV.fetch('VAPID_SUBJECT', 'mailto:admin@example.com'),
        public_key: ENV.fetch('VAPID_PUBLIC_KEY', nil),
        private_key: ENV.fetch('VAPID_PRIVATE_KEY', nil)
      }
    end
  end
end

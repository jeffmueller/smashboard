# frozen_string_literal: true

module PushHelpers
  # Delivery is skipped outright when VAPID keys are missing, so any spec that
  # asserts something was sent has to supply them.
  def with_vapid_keys
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('VAPID_SUBJECT', anything).and_return('mailto:test@example.com')
    allow(ENV).to receive(:fetch).with('VAPID_PUBLIC_KEY', nil).and_return('test-public-key')
    allow(ENV).to receive(:fetch).with('VAPID_PRIVATE_KEY', nil).and_return('test-private-key')
  end

  def sent_pushes
    @sent_pushes ||= []
  end

  def capture_pushes
    with_vapid_keys
    allow(WebPush).to receive(:payload_send) { |args| sent_pushes << args }
  end
end

RSpec.configure { |config| config.include PushHelpers }

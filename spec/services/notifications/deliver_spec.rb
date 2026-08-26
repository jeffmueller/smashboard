# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notifications::Deliver do
  let(:user) { create(:user) }
  let!(:subscription) { create(:push_subscription, user: user) }
  let(:payload) { described_class::Payload.new(title: 'Breaking', body: 'Something happened', url: '/') }

  def deliver(kind: 'breaking_news', dedupe_key: nil)
    described_class.call(user, kind, payload, dedupe_key: dedupe_key)
  end

  it 'sends a push to every registered device' do
    capture_pushes
    create(:push_subscription, user: user, endpoint: 'https://push.example.com/second')

    expect(deliver).to be(true)
    expect(sent_pushes.size).to eq(2)
  end

  it 'sends the payload as JSON the service worker can render' do
    capture_pushes

    deliver

    message = JSON.parse(sent_pushes.first[:message])
    expect(message).to include('title' => 'Breaking', 'body' => 'Something happened')
  end

  it 'respects a disabled preference' do
    capture_pushes
    create(:notification_preference, user: user, kind: 'breaking_news', enabled: false)

    expect(deliver).to be(false)
    expect(sent_pushes).to be_empty
  end

  it 'skips a kind with every channel switched off' do
    capture_pushes
    create(:notification_preference, user: user, kind: 'breaking_news', via_web_push: false, via_email: false)

    expect(deliver).to be(false)
    expect(sent_pushes).to be_empty
  end

  it 'falls back to the shipped default when the user has no preference row' do
    capture_pushes

    expect(deliver).to be(true)
  end

  describe 'deduplication' do
    it 'sends once for a given key and never again' do
      capture_pushes

      expect(deliver(dedupe_key: 'story-1')).to be(true)
      expect(deliver(dedupe_key: 'story-1')).to be(false)
      expect(sent_pushes.size).to eq(1)
    end

    it 'treats different keys as different notifications' do
      capture_pushes

      deliver(dedupe_key: 'story-1')
      deliver(dedupe_key: 'story-2')

      expect(sent_pushes.size).to eq(2)
    end

    it 'scopes the key to the user' do
      capture_pushes
      other = create(:user)
      create(:push_subscription, user: other, endpoint: 'https://push.example.com/other')

      described_class.call(user, 'breaking_news', payload, dedupe_key: 'story-1')
      described_class.call(other, 'breaking_news', payload, dedupe_key: 'story-1')

      expect(sent_pushes.size).to eq(2)
    end

    it 'sends every time when no key is given' do
      capture_pushes

      2.times { deliver }

      expect(sent_pushes.size).to eq(2)
    end
  end

  describe 'dead subscriptions' do
    # WebPush errors build their message from the response body at construction.
    let(:failed_response) { Struct.new(:body, :code).new('gone', '410') }

    it 'prunes an expired endpoint instead of failing' do
      with_vapid_keys
      allow(WebPush).to receive(:payload_send)
        .and_raise(WebPush::ExpiredSubscription.new(failed_response, 'push.example.com'))

      expect { deliver }.to change(PushSubscription, :count).by(-1)
    end

    it 'keeps the subscription on a transient failure' do
      with_vapid_keys
      allow(WebPush).to receive(:payload_send)
        .and_raise(WebPush::ResponseError.new(failed_response, 'push.example.com'))

      expect { deliver }.not_to change(PushSubscription, :count)
    end
  end

  it 'does nothing but log when VAPID keys are missing' do
    allow(WebPush).to receive(:payload_send)

    deliver

    expect(WebPush).not_to have_received(:payload_send)
    expect(subscription.reload).to be_persisted
  end
end

# frozen_string_literal: true

require 'rails_helper'

# End-to-end for the actual Web Push wire format: real VAPID signing and real
# payload encryption, with nothing about WebPush stubbed. Only the socket is
# faked, because a push service is necessarily remote and HTTPS-only.
RSpec.describe Notifications::Deliver do
  let(:user) { create(:user) }
  let(:vapid) { WebPush.generate_key }
  let(:endpoint) { 'https://fcm.googleapis.com/fcm/send/fake-device-token' }

  # What a browser's PushManager.subscribe() hands back: a P-256 public key and
  # a 16-byte auth secret.
  let(:browser_key) { OpenSSL::PKey::EC.generate('prime256v1') }
  let(:p256dh) { Base64.urlsafe_encode64(browser_key.public_key.to_bn.to_s(2), padding: false) }
  let(:auth) { Base64.urlsafe_encode64(OpenSSL::Random.random_bytes(16), padding: false) }

  let(:payload) do
    Notifications::Deliver::Payload.new(
      title: 'Design Review',
      body: 'in 10 minutes',
      url: 'https://meet.google.com/abc-defg-hij',
      tag: 'meeting-1'
    )
  end

  before do
    create(:push_subscription, user: user, endpoint: endpoint, p256dh_key: p256dh, auth_key: auth)

    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('VAPID_SUBJECT', anything).and_return('mailto:test@example.com')
    allow(ENV).to receive(:fetch).with('VAPID_PUBLIC_KEY', nil).and_return(vapid.public_key)
    allow(ENV).to receive(:fetch).with('VAPID_PRIVATE_KEY', nil).and_return(vapid.private_key)
  end

  def deliver
    described_class.call(user, 'meeting_reminder', payload)
  end

  # The assignment returns the request, which is truthy, so this both captures
  # the request and satisfies WebMock's matcher.
  def capture_request
    captured = nil
    stub_request(:post, endpoint).with { |request| captured = request }.to_return(status: 201)
    deliver
    captured
  end

  it 'posts an encrypted, VAPID-signed push to the endpoint' do
    request = stub_request(:post, endpoint).to_return(status: 201)

    expect(deliver).to be(true)
    expect(request).to have_been_made
  end

  it 'signs the request with a VAPID JWT' do
    captured = capture_request

    expect(captured.headers['Authorization']).to start_with('vapid t=')
    # The header carries unpadded base64url per RFC 8292; generate_key pads.
    expect(captured.headers['Authorization']).to include("k=#{vapid.public_key.delete('=')}")
  end

  it 'encrypts the body — the payload never travels in the clear' do
    captured = capture_request

    expect(captured.headers['Content-Encoding']).to eq('aes128gcm')
    expect(captured.body).to be_present
    expect(captured.body).not_to include('Design Review')
    expect(captured.body).not_to include('meet.google.com')
  end

  it 'drops the subscription when the push service says it is gone' do
    stub_request(:post, endpoint).to_return(status: 410)

    expect { deliver }.to change(PushSubscription, :count).by(-1)
  end

  it 'keeps the subscription when the push service is merely unhappy' do
    stub_request(:post, endpoint).to_return(status: 500)

    expect { deliver }.not_to change(PushSubscription, :count)
  end
end

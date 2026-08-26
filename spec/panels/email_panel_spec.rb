# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailPanel do
  let(:user) { create(:user) }
  let!(:fastmail) { create(:connection, user: user, provider: 'imap', label: 'Fastmail') }
  let(:panel) { user.panels.find_by!(kind: 'email') }

  def message(uid, subject: "Subject #{uid}", from: 'Dana Lee', message_id: nil)
    { uid: uid, message_id: message_id || "<#{uid}@example.com>", from: from, subject: subject,
      received_at: Time.utc(2026, 8, 25, 13, 30).iso8601, preview: 'Preview text', account: 'Fastmail' }
  end

  def stub_mailbox(unread_count:, messages: [], client: Integrations::Imap)
    allow(client).to receive(:new)
      .and_return(instance_double(client, unread: { unread_count: unread_count, messages: messages }))
  end

  it 'reads a mailbox over IMAP or the Gmail API' do
    expect(described_class).not_to be_pending
    expect(described_class.required_providers).to contain_exactly('imap', 'gmail')
  end

  it 'reports a count and previews per mailbox' do
    stub_mailbox(unread_count: 12, messages: [message(7), message(6)])

    payload = panel.presenter.fetch

    expect(payload[:total_unread]).to eq(12)
    expect(payload[:accounts].first).to include(label: 'Fastmail', unread_count: 12)
    expect(payload[:accounts].first[:messages].pluck(:uid)).to eq([7, 6])
  end

  it 'passes the configured preview limit through to the client' do
    client = instance_double(Integrations::Imap, unread: { unread_count: 0, messages: [] })
    allow(Integrations::Imap).to receive(:new).and_return(client)
    panel.update!(settings: { 'limit' => 5 })

    panel.presenter.fetch

    expect(client).to have_received(:unread).with(limit: 5)
  end

  context 'with two mailboxes' do
    let!(:gmail) { create(:connection, user: user, provider: 'imap', label: 'Gmail') }

    it 'sums unread across both' do
      allow(Integrations::Imap).to receive(:new).with(fastmail)
                                                .and_return(instance_double(Integrations::Imap,
                                                                            unread: { unread_count: 4,
                                                                                      messages: [message(1)] }))
      allow(Integrations::Imap).to receive(:new).with(gmail)
                                                .and_return(instance_double(Integrations::Imap,
                                                                            unread: { unread_count: 9,
                                                                                      messages: [message(2)] }))

      payload = panel.presenter.fetch

      expect(payload[:total_unread]).to eq(13)
      expect(payload[:accounts].pluck(:label)).to contain_exactly('Fastmail', 'Gmail')
    end

    it 'keeps working when one mailbox fails' do
      allow(Integrations::Imap).to receive(:new).with(fastmail)
                                                .and_return(instance_double(Integrations::Imap,
                                                                            unread: { unread_count: 4, messages: [] }))
      allow(Integrations::Imap).to receive(:new).with(gmail)
                                                .and_raise(Integrations::Base::AuthenticationError, 'rejected')

      payload = panel.presenter.fetch

      expect(payload[:total_unread]).to eq(4)
      expect(payload[:partial]).to be(true)
      expect(gmail.reload.status).to eq('error')
    end
  end

  it 'parks the panel in an error state when every mailbox fails' do
    allow(Integrations::Imap).to receive(:new).and_raise(Integrations::Base::Unavailable, 'server down')

    expect { panel.presenter.refresh! }.not_to raise_error
    expect(panel.reload.data_status).to eq('error')
  end

  describe 'new mail notifications' do
    let!(:device) { create(:push_subscription, user: user) }

    before { capture_pushes }

    # Most people don't want a push per message, so the shipped default is off.
    it 'stays silent by default' do
      stub_mailbox(unread_count: 1, messages: [message(7)])

      panel.presenter.refresh!

      expect(sent_pushes).to be_empty
    end

    context 'when the user switches it on' do
      before { create(:notification_preference, user: user, kind: 'email_received', via_web_push: true) }

      it 'announces a new message' do
        stub_mailbox(unread_count: 1, messages: [message(7, subject: 'Can we move standup?')])

        panel.presenter.refresh!

        expect(sent_pushes.size).to eq(1)
        expect(JSON.parse(sent_pushes.first[:message]))
          .to include('title' => 'Dana Lee', 'body' => 'Can we move standup?')
      end

      it 'stays quiet about a message it has already announced' do
        stub_mailbox(unread_count: 1, messages: [message(7)])

        3.times { panel.presenter.refresh! }

        expect(sent_pushes.size).to eq(1)
      end

      it 'announces only what is new on the next refresh' do
        stub_mailbox(unread_count: 1, messages: [message(7)])
        panel.presenter.refresh!

        stub_mailbox(unread_count: 2, messages: [message(8), message(7)])
        panel.presenter.refresh!

        expect(sent_pushes.size).to eq(2)
      end

      # Coming back from an outage to a full mailbox shouldn't be a firehose.
      it 'caps how many it announces in one refresh' do
        stub_mailbox(unread_count: 40, messages: (1..10).map { |uid| message(uid) })

        panel.presenter.refresh!

        expect(sent_pushes.size).to eq(described_class::MAX_ANNOUNCEMENTS_PER_ACCOUNT)
      end

      # UIDs are only unique within a mailbox generation; message-ids survive.
      it 'recognises the same message after a UID change' do
        stub_mailbox(unread_count: 1, messages: [message(7, message_id: '<stable@example.com>')])
        panel.presenter.refresh!

        stub_mailbox(unread_count: 1, messages: [message(99, message_id: '<stable@example.com>')])
        panel.presenter.refresh!

        expect(sent_pushes.size).to eq(1)
      end
    end
  end
end

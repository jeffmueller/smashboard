# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Imap do
  let(:connection) do
    create(:connection, provider: 'imap', label: 'Fastmail',
                        settings: { 'host' => 'imap.fastmail.com' },
                        credentials: { 'username' => 'alex@fastmail.com', 'password' => 'app-password' })
  end

  let(:client) { described_class.new(connection) }

  describe 'reading the mailbox without changing it' do
    # A plain BODY fetch sets \Seen. Rendering an unread panel with BODY would
    # mark every previewed message read and empty the panel out.
    it 'peeks at bodies rather than fetching them' do
      imap = fake_imap(unseen: 1, uids: [7], messages: [imap_message(uid: 7)])

      client.unread

      expect(imap).to have_received(:uid_fetch) do |_uids, items|
        expect(items.grep(/BODY/)).to all(start_with('BODY.PEEK['))
        expect(items).not_to include(a_string_matching(/\ABODY\[/))
      end
    end

    it 'opens the mailbox read-only' do
      imap = fake_imap(unseen: 1, uids: [7], messages: [imap_message(uid: 7)])

      client.unread

      expect(imap).to have_received(:examine).with('INBOX')
      expect(imap).not_to have_received(:select)
    end

    it 'asks STATUS for the count, so a zero-unread mailbox is never even opened' do
      imap = fake_imap(unseen: 0)

      result = client.unread

      expect(result).to eq({ unread_count: 0, messages: [] })
      expect(imap).to have_received(:status).with('INBOX', ['UNSEEN'])
      expect(imap).not_to have_received(:examine)
      expect(imap).not_to have_received(:uid_fetch)
    end

    it 'always logs out and disconnects' do
      imap = fake_imap(unseen: 0)

      client.unread

      expect(imap).to have_received(:logout)
      expect(imap).to have_received(:disconnect)
    end

    it 'still disconnects when the fetch blows up' do
      imap = fake_imap(unseen: 1, uids: [7])
      allow(imap).to receive(:uid_fetch).and_raise(StandardError, 'boom')

      expect { client.unread }.to raise_error(StandardError)
      expect(imap).to have_received(:disconnect)
    end
  end

  describe 'message previews' do
    def first_message(**overrides)
      fake_imap(unseen: 1, uids: [7], messages: [imap_message(uid: 7, **overrides)])
      client.unread[:messages].first
    end

    it 'normalises sender, subject and time' do
      message = first_message

      expect(message).to include(uid: 7, from: 'Dana Lee', subject: 'Standup notes')
      expect(message[:received_at]).to eq(Time.utc(2026, 8, 25, 13, 30))
    end

    it 'falls back to the address when the sender has no display name' do
      expect(first_message(from_name: nil)[:from]).to eq('dana@example.com')
    end

    it 'decodes a MIME-encoded subject' do
      encoded = '=?UTF-8?B?U2NoZWTDvWxlIGNoYW5nZQ==?='

      expect(first_message(subject: encoded)[:subject]).to eq('Schedýle change')
    end

    it 'labels a message with no subject' do
      expect(first_message(subject: nil)[:subject]).to eq('(no subject)')
    end

    it 'previews a plain text body' do
      expect(first_message(body: "Hi there,\r\n\r\nCan we move standup?\r\n")[:preview])
        .to eq('Hi there, Can we move standup?')
    end

    it 'decodes a quoted-printable body' do
      message = first_message(encoding: 'quoted-printable', body: 'Caf=C3=A9 at 3pm=3F')

      expect(message[:preview]).to eq('Café at 3pm?')
    end

    it 'strips tags out of an HTML body' do
      message = first_message(content_type: 'text/html; charset=UTF-8',
                              body: '<html><body><p>Hello <b>there</b></p></body></html>')

      expect(message[:preview]).to eq('Hello there')
    end

    it 'takes the plain text part of a multipart message' do
      boundary = 'sep'
      body = <<~BODY
        --#{boundary}
        Content-Type: text/plain; charset=UTF-8

        The plain version.
        --#{boundary}
        Content-Type: text/html; charset=UTF-8

        <p>The HTML version.</p>
        --#{boundary}--
      BODY

      message = first_message(content_type: %(multipart/alternative; boundary="#{boundary}"), body: body)

      expect(message[:preview]).to eq('The plain version.')
    end

    it 'still previews something when the body is truncated mid-MIME' do
      message = first_message(content_type: 'multipart/alternative; boundary="sep"',
                              body: "--sep\nContent-Type: text/plain\n\nCut off half way thr")

      expect(message[:preview]).to be_present
    end

    it 'lists the newest unread first' do
      fake_imap(unseen: 3, uids: [5, 6, 7],
                messages: [imap_message(uid: 7), imap_message(uid: 6), imap_message(uid: 5)])

      expect(client.unread(limit: 3)[:messages].pluck(:uid)).to eq([7, 6, 5])
    end

    it 'asks for only as many messages as the limit allows' do
      imap = fake_imap(unseen: 40, uids: (1..40).to_a, messages: [imap_message(uid: 40)])

      client.unread(limit: 3)

      expect(imap).to have_received(:uid_fetch).with([40, 39, 38], anything)
    end
  end

  describe 'host resolution' do
    it 'uses the configured host' do
      imap = fake_imap(unseen: 0)

      client.unread

      expect(Net::IMAP).to have_received(:new).with('imap.fastmail.com', hash_including(port: 993, ssl: true))
      expect(imap).to have_received(:login).with('alex@fastmail.com', 'app-password')
    end

    it 'infers a known provider from the address when no host is set' do
      connection.update!(settings: {}, credentials: { 'username' => 'alex@gmail.com', 'password' => 'x' })
      fake_imap(unseen: 0)

      client.unread

      expect(Net::IMAP).to have_received(:new).with('imap.gmail.com', anything)
    end

    it 'says so plainly when the provider is unknown and no host is set' do
      connection.update!(settings: {}, credentials: { 'username' => 'alex@example.org', 'password' => 'x' })

      expect { client.unread }
        .to raise_error(Integrations::Base::Unavailable, /example\.org isn't a known provider/)
    end

    it 'honours a custom port, mailbox and a disabled TLS for a local server' do
      connection.update!(settings: { 'host' => 'localhost', 'port' => '1143', 'mailbox' => 'Archive',
                                     'ssl' => 'false' })
      imap = fake_imap(unseen: 0)

      client.unread

      expect(Net::IMAP).to have_received(:new).with('localhost', hash_including(port: 1143, ssl: false))
      expect(imap).to have_received(:status).with('Archive', ['UNSEEN'])
    end
  end

  describe 'failures' do
    it 'surfaces the server text on a rejected password' do
      imap = instance_double(Net::IMAP, disconnected?: false)
      allow(Net::IMAP).to receive(:new).and_return(imap)
      allow(imap).to receive(:disconnect)
      allow(imap).to receive(:logout)
      response = Net::IMAP::TaggedResponse.new(
        'a1', 'NO', Net::IMAP::ResponseText.new(nil, 'Application-specific password required'), nil
      )
      allow(imap).to receive(:login).and_raise(Net::IMAP::NoResponseError.new(response))

      expect { client.unread }
        .to raise_error(Integrations::Base::AuthenticationError, /Application-specific password required/)
    end

    it 'reports an unreachable server as unavailable' do
      allow(Net::IMAP).to receive(:new).and_raise(Errno::ECONNREFUSED)

      expect { client.unread }.to raise_error(Integrations::Base::Unavailable, /could not reach/)
    end

    it 'reports a TLS failure as unavailable' do
      allow(Net::IMAP).to receive(:new).and_raise(OpenSSL::SSL::SSLError, 'bad handshake')

      expect { client.unread }.to raise_error(Integrations::Base::Unavailable, /could not reach/)
    end
  end
end

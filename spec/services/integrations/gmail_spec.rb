# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Gmail do
  let(:connection) do
    create(:connection, provider: 'gmail', label: 'Personal Gmail',
                        settings: {}, credentials: { 'refresh_token' => 'refresh-abc' })
  end

  let(:client) { described_class.new(connection) }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('GOOGLE_CLIENT_ID').and_return('client-id')
    allow(ENV).to receive(:[]).with('GOOGLE_CLIENT_SECRET').and_return('client-secret')
    stub_request(:post, 'https://oauth2.googleapis.com/token')
      .to_return(status: 200, body: { access_token: 'ya29.access', expires_in: 3599 }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def json(body, status: 200)
    { status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def stub_list(ids, estimate: ids.size)
    stub_request(:get, %r{gmail/v1/users/me/messages\?})
      .to_return(json({ messages: ids.map { |id| { id: id, threadId: id } },
                        resultSizeEstimate: estimate }))
  end

  def stub_message(id, from: 'Dana Lee <dana@example.com>', subject: 'Standup moved',
                   snippet: 'Pushing standup back fifteen minutes', internal_date: '1787700000000')
    stub_request(:get, %r{gmail/v1/users/me/messages/#{id}})
      .to_return(json({ id: id, snippet: snippet, internalDate: internal_date,
                        payload: { headers: [{ name: 'From', value: from },
                                             { name: 'Subject', value: subject }] } }))
  end

  describe '#unread' do
    it 'authenticates with a token obtained from the refresh token' do
      request = stub_list([])

      client.unread

      expect(request.with(headers: { 'Authorization' => 'Bearer ya29.access' })).to have_been_made
    end

    it 'searches unread inbox mail by default' do
      request = stub_list([])

      client.unread

      expect(request.with(query: hash_including('q' => 'is:unread in:inbox'))).to have_been_made
    end

    it 'honours a custom search' do
      connection.update!(settings: { 'query' => 'is:unread -category:promotions' })
      request = stub_list([])

      client.unread

      expect(request.with(query: hash_including('q' => 'is:unread -category:promotions'))).to have_been_made
    end

    it 'reports the count Gmail gives for the search' do
      stub_list(%w[m1], estimate: 42)
      stub_message('m1')

      expect(client.unread[:unread_count]).to eq(42)
    end

    it 'asks for metadata only, never message bodies' do
      stub_list(%w[m1])
      request = stub_message('m1')

      client.unread

      expect(request.with(query: hash_including('format' => 'metadata'))).to have_been_made
    end

    it 'fetches nothing further when the search matches nothing' do
      stub_list([], estimate: 0)

      expect(client.unread).to eq({ unread_count: 0, messages: [] })
    end
  end

  describe 'message previews' do
    def first_message(**overrides)
      stub_list(%w[m1])
      stub_message('m1', **overrides)
      client.unread[:messages].first
    end

    it 'prefers the sender display name over the address' do
      expect(first_message(from: 'Dana Lee <dana@example.com>')[:from]).to eq('Dana Lee')
    end

    it 'falls back to the address when there is no display name' do
      expect(first_message(from: 'dana@example.com')[:from]).to eq('dana@example.com')
    end

    it 'decodes a MIME-encoded subject' do
      expect(first_message(subject: '=?UTF-8?B?U2NoZWTDvWxlIGNoYW5nZQ==?=')[:subject]).to eq('Schedýle change')
    end

    # Gmail snippets arrive HTML-escaped.
    it 'unescapes the snippet' do
      expect(first_message(snippet: 'It&#39;s at 3pm &amp; running long')[:preview])
        .to eq("It's at 3pm & running long")
    end

    it 'converts the millisecond timestamp' do
      expect(first_message(internal_date: '1787700000000')[:received_at])
        .to eq(Time.zone.at(1_787_700_000).utc)
    end

    it 'labels a message with no subject' do
      stub_list(%w[m1])
      stub_request(:get, %r{messages/m1}).to_return(json({ id: 'm1', payload: { headers: [] } }))

      expect(client.unread[:messages].first[:subject]).to eq('(no subject)')
    end

    # One unreadable message shouldn't cost the whole mailbox.
    it 'skips a message it cannot read and keeps the rest' do
      stub_list(%w[m1 m2])
      stub_request(:get, %r{messages/m1}).to_return(json({}, status: 500))
      stub_message('m2')

      messages = client.unread[:messages]

      expect(messages.size).to eq(1)
      expect(messages.first[:uid]).to eq('m2')
    end
  end

  describe 'failures' do
    it 'raises AuthenticationError when the grant is dead' do
      stub_request(:post, 'https://oauth2.googleapis.com/token')
        .to_return(json({ error: 'invalid_grant' }, status: 400))

      expect { client.unread }
        .to raise_error(Integrations::Base::AuthenticationError, /needs granting again/)
    end

    it 'treats a Google outage as transient' do
      stub_request(:post, 'https://oauth2.googleapis.com/token').to_return(json({}, status: 503))

      expect { client.unread }.to raise_error(Integrations::Base::Unavailable)
    end

    it 'raises AuthenticationError with no refresh token stored' do
      connection.update!(credentials: {})

      expect { client.unread }
        .to raise_error(Integrations::Base::AuthenticationError, /no Google refresh token/)
    end
  end
end

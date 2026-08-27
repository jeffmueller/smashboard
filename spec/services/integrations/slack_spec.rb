# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Slack do
  let(:connection) do
    create(:connection, provider: 'slack', label: 'Work Slack',
                        settings: {}, credentials: { 'user_token' => 'xoxp-secret' })
  end

  let(:client) { described_class.new(connection) }

  def slack_json(body)
    { status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def stub_method(method, body)
    stub_request(:get, %r{slack\.com/api/#{Regexp.escape(method)}}).to_return(slack_json(body))
  end

  def channel(id, name: nil, is_im: false, is_mpim: false)
    { id: id, name: name, is_im: is_im, is_mpim: is_mpim }.compact
  end

  def stub_conversations(*channels, next_cursor: '')
    stub_method('users.conversations',
                { ok: true, channels: channels, response_metadata: { next_cursor: next_cursor } })
  end

  def stub_info(id, unread_display:, unread: nil, name: nil, user: nil)
    stub_request(:get, %r{slack\.com/api/conversations\.info})
      .with(query: hash_including('channel' => id))
      .to_return(slack_json({ ok: true,
                              channel: { id: id, name: name, user: user,
                                         unread_count: unread || unread_display,
                                         unread_count_display: unread_display }.compact }))
  end

  describe '#workspace' do
    it 'identifies the workspace' do
      stub_method('auth.test', { ok: true, team: 'Acme', team_id: 'T1', user: 'alex',
                                 url: 'https://acme.slack.com/' })

      expect(client.workspace).to include(team: 'Acme', user: 'alex', url: 'https://acme.slack.com/')
    end

    it 'authenticates with the user token' do
      request = stub_method('auth.test', { ok: true, team: 'Acme' })

      client.workspace

      expect(request.with(headers: { 'Authorization' => 'Bearer xoxp-secret' })).to have_been_made
    end
  end

  describe '#unread' do
    # Any direct message with unreads triggers a name lookup for the display
    # list, so every counting example needs this available.
    before { stub_method('users.info', { ok: true, user: { real_name: 'Dana Lee', profile: {} } }) }

    it 'skips archived and muted conversations when listing' do
      request = stub_conversations
      client.unread

      expect(request.with(query: hash_including('exclude_archived' => 'true',
                                                'exclude_muted' => 'true',
                                                'types' => 'im,mpim,private_channel,public_channel')))
        .to have_been_made
    end

    # Slack omits the unread fields entirely for channels when the token lacks
    # the history scopes. Coercing that to zero reported a confident "nothing
    # unread" for every channel in the workspace, with no error anywhere.
    describe 'a conversation Slack returns no unread count for' do
      before do
        stub_conversations(channel('C1', name: 'general'), channel('D1', is_im: true))
        stub_info('C1', unread_display: nil)
        stub_info('D1', unread_display: 4, user: 'U1')
      end

      it 'is not counted as zero unread' do
        expect(client.unread[:conversations_uncounted]).to eq(1)
      end

      it 'does not stop the conversations Slack does answer for' do
        result = client.unread

        expect(result[:dm_unread]).to eq(4)
        expect(result[:channel_unread]).to eq(0)
        expect(result[:conversations_checked]).to eq(2)
      end

      it 'stays out of the named list rather than appearing as a zero' do
        expect(client.unread[:top].pluck(:name)).not_to include('#general')
      end
    end

    it 'reports nothing uncounted when Slack answers for everything' do
      stub_conversations(channel('C1', name: 'general'))
      stub_info('C1', unread_display: 0)

      expect(client.unread[:conversations_uncounted]).to eq(0)
    end

    # The *_display count is what Slack badges with; the raw count includes
    # joins and leaves nobody thinks of as a message.
    it 'counts the display total, not the raw one' do
      stub_conversations(channel('C1', name: 'general'))
      stub_info('C1', unread_display: 3, unread: 47)

      expect(client.unread[:channel_unread]).to eq(3)
    end

    it 'separates direct messages from channels' do
      stub_conversations(channel('D1', is_im: true), channel('C1', name: 'general'))
      stub_info('D1', unread_display: 4, user: 'U1')
      stub_info('C1', unread_display: 6, name: 'general')

      counts = client.unread

      expect(counts[:dm_unread]).to eq(4)
      expect(counts[:channel_unread]).to eq(6)
    end

    it 'follows pagination when listing conversations' do
      stub_request(:get, /users\.conversations/).to_return(
        slack_json({ ok: true, channels: [channel('C1', name: 'one')],
                     response_metadata: { next_cursor: 'more' } }),
        slack_json({ ok: true, channels: [channel('C2', name: 'two')],
                     response_metadata: { next_cursor: '' } })
      )
      stub_info('C1', unread_display: 1, name: 'one')
      stub_info('C2', unread_display: 2, name: 'two')

      expect(client.unread[:conversations_checked]).to eq(2)
    end

    # Slack has no bulk unread endpoint, so the fan-out is budgeted and DMs —
    # the actionable ones — go first.
    it 'spends the budget on direct messages before channels' do
      stub_conversations(channel('C1', name: 'one'), channel('C2', name: 'two'),
                         channel('D1', is_im: true))
      stub_info('D1', unread_display: 5, user: 'U1')
      stub_info('C1', unread_display: 9, name: 'one')

      counts = client.unread(budget: 2)

      expect(counts[:dm_unread]).to eq(5)
      expect(counts[:conversations_checked]).to eq(2)
      expect(counts[:conversations_skipped]).to eq(1)
    end

    it 'reports nothing skipped when the budget covers everything' do
      stub_conversations(channel('C1', name: 'one'))
      stub_info('C1', unread_display: 0, name: 'one')

      expect(client.unread[:conversations_skipped]).to be_zero
    end

    it 'names the busiest conversations, channels with a hash' do
      stub_conversations(channel('C1', name: 'general'), channel('D1', is_im: true))
      stub_info('C1', unread_display: 2, name: 'general')
      stub_info('D1', unread_display: 9, user: 'U1')

      top = client.unread[:top]

      expect(top.first).to include(name: 'Dana Lee', direct: true, unread: 9)
      expect(top.last).to include(name: '#general', direct: false, unread: 2)
    end

    it 'leaves quiet conversations out of the named list' do
      stub_conversations(channel('C1', name: 'general'))
      stub_info('C1', unread_display: 0, name: 'general')

      expect(client.unread[:top]).to be_empty
    end

    # Hitting the limit mid-count shouldn't cost the whole workspace.
    it 'keeps what it counted when Slack starts rate limiting' do
      stub_conversations(channel('C1', name: 'one'), channel('C2', name: 'two'))
      stub_info('C1', unread_display: 4, name: 'one')
      stub_request(:get, /conversations\.info/).with(query: hash_including('channel' => 'C2'))
                                               .to_return(slack_json({ ok: false, error: 'ratelimited' }))

      expect(client.unread[:channel_unread]).to eq(4)
    end
  end

  describe 'the ok:false envelope' do
    # Slack answers failures with HTTP 200. Reading the status alone would treat
    # a rejected token as a successful, empty response.
    it 'treats a 200 with ok:false as a failure' do
      stub_method('auth.test', { ok: false, error: 'invalid_auth' })

      expect { client.workspace }
        .to raise_error(Integrations::Base::AuthenticationError, /invalid_auth/)
    end

    it 'names the scope the token is missing' do
      stub_method('auth.test', { ok: false, error: 'missing_scope',
                                 needed: 'im:read', provided: 'channels:read' })

      expect { client.workspace }
        .to raise_error(Integrations::Base::AuthenticationError, /missing the im:read scope/)
    end

    it 'reports a revoked token as an auth failure' do
      stub_method('auth.test', { ok: false, error: 'token_revoked' })

      expect { client.workspace }.to raise_error(Integrations::Base::AuthenticationError)
    end

    it 'reports rate limiting distinctly' do
      stub_method('users.conversations', { ok: false, error: 'ratelimited' })

      expect { client.unread }.to raise_error(Integrations::Base::RateLimited)
    end

    it 'reports anything else as unavailable' do
      stub_method('users.conversations', { ok: false, error: 'fatal_error' })

      expect { client.unread }.to raise_error(Integrations::Base::Unavailable, /fatal_error/)
    end
  end

  describe 'configuration' do
    it 'refuses to run without a token' do
      connection.update!(credentials: {})

      expect { client.workspace }
        .to raise_error(Integrations::Base::AuthenticationError, /no Slack user token/)
    end

    it 'reports a transport failure as unavailable' do
      stub_request(:get, %r{slack\.com/api/auth\.test}).to_return(status: 503, body: '{}')

      expect { client.workspace }.to raise_error(Integrations::Base::Unavailable)
    end
  end
end

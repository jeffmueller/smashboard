# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Oauth::Slack do
  let(:redirect_uri) { 'https://smashboard.test/oauth/slack/callback' }
  let(:scopes) { %w[channels:read im:read] }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('SLACK_CLIENT_ID', nil).and_return('client-id')
    allow(ENV).to receive(:fetch).with('SLACK_CLIENT_SECRET', nil).and_return('client-secret')
  end

  describe '.authorize_url' do
    subject(:url) { described_class.authorize_url(redirect_uri: redirect_uri, state: 'state-123', scopes: scopes) }

    # `scope` would ask for a bot token, and a bot's unread count is not the
    # user's. This is the whole difference.
    it 'asks for user scopes, not bot scopes' do
      expect(url).to include('user_scope=')
      expect(url).not_to match(/[?&]scope=/)
    end

    it 'comma-separates the scopes' do
      expect(url).to include(CGI.escape('channels:read,im:read'))
    end

    it 'carries the state and redirect' do
      expect(url).to include('state=state-123', CGI.escape(redirect_uri))
    end
  end

  describe '.exchange' do
    def stub_access(body)
      stub_request(:post, 'https://slack.com/api/oauth.v2.access')
        .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    # The user token is nested under authed_user; the top-level access_token is
    # the bot's.
    it 'takes the token from authed_user, not the top level' do
      stub_access({ ok: true, access_token: 'xoxb-bot', team: { name: 'Acme', id: 'T1' },
                    authed_user: { id: 'U1', access_token: 'xoxp-user', token_type: 'user' } })

      result = described_class.exchange(code: 'code-1', redirect_uri: redirect_uri)

      expect(result.credentials).to eq({ 'user_token' => 'xoxp-user' })
    end

    it 'labels the connection with the workspace' do
      stub_access({ ok: true, team: { name: 'Acme', id: 'T1' },
                    authed_user: { access_token: 'xoxp-user' } })

      expect(described_class.exchange(code: 'code-1', redirect_uri: redirect_uri).label).to eq('Acme')
    end

    # An app configured with only bot scopes comes back without one.
    it 'refuses a grant that produced no user token' do
      stub_access({ ok: true, access_token: 'xoxb-bot', team: { name: 'Acme' } })

      expect { described_class.exchange(code: 'code-1', redirect_uri: redirect_uri) }
        .to raise_error(described_class::Error, /no user token/)
    end

    # Slack reports failures as HTTP 200 with ok:false.
    it 'treats a 200 with ok:false as a failure' do
      stub_access({ ok: false, error: 'invalid_code' })

      expect { described_class.exchange(code: 'stale', redirect_uri: redirect_uri) }
        .to raise_error(described_class::Error, /invalid_code/)
    end
  end

  describe 'without credentials configured' do
    before { allow(ENV).to receive(:fetch).with('SLACK_CLIENT_ID', nil).and_return(nil) }

    it 'is not configured' do
      expect(described_class).not_to be_configured
    end

    it 'refuses to build an authorize URL' do
      expect { described_class.authorize_url(redirect_uri: redirect_uri, state: 'x', scopes: scopes) }
        .to raise_error(described_class::NotConfigured)
    end
  end
end

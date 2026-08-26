# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Oauth::Google do
  let(:redirect_uri) { 'https://smashboard.test/oauth/google/callback' }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('GOOGLE_CLIENT_ID', nil).and_return('client-id')
    allow(ENV).to receive(:fetch).with('GOOGLE_CLIENT_SECRET', nil).and_return('client-secret')
  end

  describe '.authorize_url' do
    subject(:url) do
      described_class.authorize_url(redirect_uri: redirect_uri, state: 'state-123', scopes: scopes)
    end

    let(:scopes) { ['https://www.googleapis.com/auth/calendar.readonly'] }

    # Without offline access Google issues no refresh token at all — only an
    # access token that dies in an hour.
    it 'requests offline access' do
      expect(url).to include('access_type=offline')
    end

    # Without this, a second authorization for an already-granted account comes
    # back with no refresh token.
    it 'forces the consent screen' do
      expect(url).to include('prompt=consent')
    end

    it 'carries the state, redirect and scopes' do
      expect(url).to include('state=state-123')
      expect(url).to include(CGI.escape(redirect_uri))
      expect(url).to include(CGI.escape('https://www.googleapis.com/auth/calendar.readonly'))
    end

    # Enough identity to name the connection, and nothing more.
    it 'always adds the identity scope alongside whatever was asked for' do
      expect(url).to include(CGI.escape(described_class::IDENTITY_SCOPE))
    end

    it 'carries the scopes it was given, so Gmail and Calendar differ' do
      gmail = described_class.authorize_url(redirect_uri: redirect_uri, state: 'x',
                                            scopes: ['https://www.googleapis.com/auth/gmail.readonly'])

      expect(gmail).to include(CGI.escape('auth/gmail.readonly'))
      expect(gmail).not_to include(CGI.escape('auth/calendar'))
    end
  end

  describe '.exchange' do
    def stub_token(body, status: 200)
      stub_request(:post, 'https://oauth2.googleapis.com/token')
        .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    def stub_userinfo(email)
      stub_request(:get, 'https://www.googleapis.com/oauth2/v2/userinfo')
        .to_return(status: 200, body: { email: email }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'returns the refresh token and the account it belongs to' do
      stub_token({ refresh_token: '1//refresh', access_token: 'ya29.access', expires_in: 3599 })
      stub_userinfo('dana@example.com')

      result = described_class.exchange(code: 'code-1', redirect_uri: redirect_uri)

      expect(result.credentials).to eq({ 'refresh_token' => '1//refresh' })
      expect(result.label).to eq('dana@example.com')
    end

    it 'sends the code and client credentials' do
      request = stub_token({ refresh_token: '1//refresh' })
      stub_userinfo('dana@example.com')

      described_class.exchange(code: 'code-1', redirect_uri: redirect_uri)

      expect(request.with { |r| r.body.include?('grant_type=authorization_code') && r.body.include?('code-1') })
        .to have_been_made
    end

    # A token we cannot refresh is worthless, so this is a failure not a warning.
    it 'refuses a grant that came back without a refresh token' do
      stub_token({ access_token: 'ya29.access' })

      expect { described_class.exchange(code: 'code-1', redirect_uri: redirect_uri) }
        .to raise_error(described_class::Error, /already granted access/)
    end

    it 'surfaces what Google said when it refuses the code' do
      stub_token({ error: 'invalid_grant', error_description: 'Bad Request' }, status: 400)

      expect { described_class.exchange(code: 'stale', redirect_uri: redirect_uri) }
        .to raise_error(described_class::Error, /invalid_grant/)
    end

    # A missing label is cosmetic; throwing away a token we just obtained is not.
    it 'keeps the token even when the account lookup fails' do
      stub_token({ refresh_token: '1//refresh', access_token: 'ya29.access' })
      stub_request(:get, %r{oauth2/v2/userinfo}).to_return(status: 500, body: '{}')

      result = described_class.exchange(code: 'code-1', redirect_uri: redirect_uri)

      expect(result.credentials['refresh_token']).to eq('1//refresh')
      expect(result.label).to be_nil
    end
  end

  describe 'without credentials configured' do
    before do
      allow(ENV).to receive(:fetch).with('GOOGLE_CLIENT_ID', nil).and_return(nil)
      allow(ENV).to receive(:fetch).with('GOOGLE_CLIENT_SECRET', nil).and_return(nil)
    end

    it 'is not configured' do
      expect(described_class).not_to be_configured
    end

    it 'refuses to build an authorize URL' do
      expect { described_class.authorize_url(redirect_uri: redirect_uri, state: 'x', scopes: []) }
        .to raise_error(described_class::NotConfigured)
    end
  end
end

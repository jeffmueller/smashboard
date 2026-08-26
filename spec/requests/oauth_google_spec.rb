# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Connect with Google' do
  let(:user) { create(:user) }

  before do
    sign_in user
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('GOOGLE_CLIENT_ID', nil).and_return('client-id')
    allow(ENV).to receive(:fetch).with('GOOGLE_CLIENT_SECRET', nil).and_return('client-secret')
  end

  def stub_google(refresh_token: '1//refresh', email: 'dana@example.com')
    stub_request(:post, 'https://oauth2.googleapis.com/token')
      .to_return(status: 200, body: { refresh_token: refresh_token, access_token: 'ya29' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, %r{oauth2/v2/userinfo})
      .to_return(status: 200, body: { email: email }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  # Follows the redirect to Google and pulls the state back out, the way the
  # browser would carry it.
  def begin_flow(connection_id: nil)
    get oauth_google_path(provider: 'google_calendar', connection_id: connection_id)
    Rack::Utils.parse_query(URI.parse(response.location).query)['state']
  end

  describe 'starting the flow' do
    it 'sends the user to Google with offline access and a forced consent screen' do
      get oauth_google_path(provider: 'google_calendar')

      expect(response).to redirect_to(%r{\Ahttps://accounts\.google\.com/})
      expect(response.location).to include('access_type=offline', 'prompt=consent')
    end

    it 'says what is missing when the server has no Google credentials' do
      allow(ENV).to receive(:fetch).with('GOOGLE_CLIENT_ID', nil).and_return(nil)

      get oauth_google_path(provider: 'google_calendar')

      expect(response).to redirect_to(connections_path)
      expect(flash[:alert]).to include('GOOGLE_CLIENT_ID', 'redirect URI')
    end

    it 'sends the picker straight here rather than to an empty form' do
      get new_connection_path(provider: 'google_calendar')

      expect(response).to redirect_to(oauth_google_path(provider: 'google_calendar'))
    end
  end

  describe 'the callback' do
    it 'creates a connection labelled with the Google account' do
      state = begin_flow
      stub_google(email: 'dana@example.com')

      expect { get oauth_google_callback_path(code: 'code-1', state: state) }
        .to change(user.connections, :count).by(1)

      connection = user.connections.find_by!(provider: 'google_calendar')
      expect(connection.label).to eq('dana@example.com')
      expect(connection.credential('refresh_token')).to eq('1//refresh')
    end

    it 're-authorizes an existing connection instead of making another' do
      connection = create(:connection, user: user, provider: 'google_calendar', label: 'Work calendar',
                                       credentials: { 'refresh_token' => 'old' })
      state = begin_flow(connection_id: connection.id)
      stub_google

      expect { get oauth_google_callback_path(code: 'code-1', state: state) }
        .not_to change(user.connections, :count)

      expect(connection.reload.credential('refresh_token')).to eq('1//refresh')
      expect(connection.label).to eq('Work calendar')
    end

    # The state parameter is the only thing stopping an attacker from having
    # their own Google account connected to somebody else's dashboard.
    it 'rejects a callback whose state does not match' do
      begin_flow
      stub_google

      expect { get oauth_google_callback_path(code: 'code-1', state: 'forged') }
        .not_to change(Connection, :count)

      expect(flash[:alert]).to include('could not be verified')
    end

    it 'rejects a callback with no state at all' do
      begin_flow
      stub_google

      get oauth_google_callback_path(code: 'code-1')

      expect(flash[:alert]).to include('could not be verified')
      expect(Connection.count).to be_zero
    end

    # A replayed callback must not work twice.
    it 'consumes the state so it cannot be reused' do
      state = begin_flow
      stub_google
      get oauth_google_callback_path(code: 'code-1', state: state)

      expect { get oauth_google_callback_path(code: 'code-2', state: state) }
        .not_to change(Connection, :count)
    end

    it 'handles the user saying no' do
      state = begin_flow

      get oauth_google_callback_path(error: 'access_denied', state: state)

      expect(flash[:alert]).to include('cancelled')
      expect(Connection.count).to be_zero
    end

    it 'reports a grant that came back with no refresh token' do
      state = begin_flow
      stub_request(:post, 'https://oauth2.googleapis.com/token')
        .to_return(status: 200, body: { access_token: 'ya29' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      get oauth_google_callback_path(code: 'code-1', state: state)

      expect(flash[:alert]).to include('no refresh token')
      expect(Connection.count).to be_zero
    end

    it "does not re-authorize somebody else's connection" do
      theirs = create(:connection, user: create(:user), provider: 'google_calendar',
                                   credentials: { 'refresh_token' => 'theirs' })
      state = begin_flow(connection_id: theirs.id)
      stub_google

      get oauth_google_callback_path(code: 'code-1', state: state)

      expect(theirs.reload.credential('refresh_token')).to eq('theirs')
      expect(user.connections.where(provider: 'google_calendar').count).to eq(1)
    end
  end
end

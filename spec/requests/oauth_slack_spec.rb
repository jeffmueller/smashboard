# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Connect with Slack' do
  let(:user) { create(:user) }

  before do
    sign_in user
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('SLACK_CLIENT_ID', nil).and_return('client-id')
    allow(ENV).to receive(:fetch).with('SLACK_CLIENT_SECRET', nil).and_return('client-secret')
  end

  def stub_access(team: 'Acme', token: 'xoxp-user', team_id: 'T1')
    stub_request(:post, 'https://slack.com/api/oauth.v2.access')
      .to_return(status: 200,
                 body: { ok: true, team: { name: team, id: team_id },
                         authed_user: { id: 'U1', access_token: token } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def begin_flow(connection_id: nil)
    get oauth_slack_path(provider: 'slack', connection_id: connection_id)
    Rack::Utils.parse_query(URI.parse(response.location).query)['state']
  end

  it 'sends the user to Slack asking for user scopes' do
    get oauth_slack_path(provider: 'slack')

    expect(response).to redirect_to(%r{\Ahttps://slack\.com/oauth/v2/authorize})
    expect(response.location).to include('user_scope=')
  end

  it 'says what is missing when the server has no Slack credentials' do
    allow(ENV).to receive(:fetch).with('SLACK_CLIENT_ID', nil).and_return(nil)

    get oauth_slack_path(provider: 'slack')

    expect(flash[:alert]).to include('SLACK_CLIENT_ID', 'redirect URL')
  end

  it 'creates a connection named after the workspace' do
    state = begin_flow
    stub_access(team: 'Acme')

    expect { get oauth_slack_callback_path(code: 'code-1', state: state) }
      .to change(user.connections, :count).by(1)

    connection = user.connections.find_by!(provider: 'slack')
    expect(connection.label).to eq('Acme')
    expect(connection.credential('user_token')).to eq('xoxp-user')
    expect(connection.authorized_at).to be_present
  end

  it 'adds a second workspace rather than replacing the first' do
    create(:connection, user: user, provider: 'slack', label: 'Acme',
                        credentials: { 'user_token' => 'xoxp-one' })
    state = begin_flow
    stub_access(team: 'Other Co', token: 'xoxp-two')

    expect { get oauth_slack_callback_path(code: 'code-1', state: state) }
      .to change(user.connections, :count).by(1)

    expect(user.connections.where(provider: 'slack').pluck(:label)).to contain_exactly('Acme', 'Other Co')
  end

  # Identity is the team id, so signing in to a workspace already connected
  # refreshes that connection rather than colliding with its label.
  it 'refreshes an existing workspace instead of adding a duplicate' do
    existing = create(:connection, user: user, provider: 'slack', label: 'Acme',
                                   settings: { 'external_id' => 'T1' },
                                   credentials: { 'user_token' => 'xoxp-stale' })
    state = begin_flow
    stub_access(team: 'Acme', token: 'xoxp-fresh', team_id: 'T1')

    expect { get oauth_slack_callback_path(code: 'code-1', state: state) }
      .not_to change(user.connections, :count)

    expect(existing.reload.credential('user_token')).to eq('xoxp-fresh')
  end

  it 'records the workspace id so it can be recognised next time' do
    state = begin_flow
    stub_access(team: 'Acme', team_id: 'T99')

    get oauth_slack_callback_path(code: 'code-1', state: state)

    expect(user.connections.find_by!(provider: 'slack').settings['external_id']).to eq('T99')
  end

  # Labels are unique per provider, and two workspaces can genuinely share a
  # name — that must not be a 500 on an otherwise successful sign-in.
  it 'numbers a second workspace that has the same name as the first' do
    create(:connection, user: user, provider: 'slack', label: 'Acme',
                        settings: { 'external_id' => 'T1' })
    state = begin_flow
    stub_access(team: 'Acme', team_id: 'T2', token: 'xoxp-two')

    expect { get oauth_slack_callback_path(code: 'code-1', state: state) }
      .to change(user.connections, :count).by(1)

    expect(user.connections.where(provider: 'slack').pluck(:label)).to contain_exactly('Acme', 'Acme (2)')
  end

  it 'rejects a callback whose state does not match' do
    begin_flow
    stub_access

    expect { get oauth_slack_callback_path(code: 'code-1', state: 'forged') }
      .not_to change(Connection, :count)

    expect(flash[:alert]).to include('could not be verified')
  end

  # Every flow shares one session key for its state, so a Google state matches
  # here too. Without a provider check this stored a Slack token on a
  # google_calendar connection — valid-looking and permanently broken.
  it 'does not let a Google state complete a Slack callback' do
    allow(ENV).to receive(:fetch).with('GOOGLE_CLIENT_ID', nil).and_return('client-id')
    allow(ENV).to receive(:fetch).with('GOOGLE_CLIENT_SECRET', nil).and_return('client-secret')
    get oauth_google_path(provider: 'google_calendar')
    google_state = Rack::Utils.parse_query(URI.parse(response.location).query)['state']
    stub_access

    expect { get oauth_slack_callback_path(code: 'code-1', state: google_state) }
      .not_to change(Connection, :count)

    expect(flash[:alert]).to include('could not be verified')
  end

  it 'refuses to start a Slack flow for a provider that is not Slack' do
    get oauth_slack_path(provider: 'google_calendar')

    expect(response).to redirect_to(connections_path)
    expect(flash[:alert]).to include("isn't something you sign in to")
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Connections' do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'choosing what to connect' do
    it 'offers a picker rather than a form when no provider is chosen' do
      get new_connection_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Mailbox (IMAP)', 'Home Assistant', 'Slack')
      expect(response.body).not_to include('Credentials')
    end

    it 'flags the provider that needs no credential' do
      get new_connection_path

      expect(response.body).to include('No key needed')
    end
  end

  describe 'the form for one provider' do
    # The old form asked for the same generic fields whatever you picked.
    it 'asks only for that provider\'s fields' do
      get new_connection_path(provider: 'imap')

      expect(response.body).to include('connection[credentials][password]')
      expect(response.body).to include('connection[settings][host]')
      expect(response.body).not_to include('connection[credentials][access_token]')
    end

    it 'explains where the credential comes from' do
      get new_connection_path(provider: 'imap')

      expect(response.body).to include('App password')
      expect(response.body).to include('Fastmail')
    end

    # The news feed's host and cookie name are configuration, not constants, so
    # the form has to offer both alongside the password.
    it 'offers the news feed its URL, its cookie name and its password' do
      get new_connection_path(provider: 'news_feed')

      expect(response.body).to include('connection[settings][base_url]')
      expect(response.body).to include('connection[settings][cookie_name]')
      expect(response.body).to include('connection[credentials][password]')
    end

    # Providers that sign in have nothing to type, so the form is skipped.
    it 'sends a sign-in provider straight into its flow' do
      get new_connection_path(provider: 'slack')

      expect(response).to redirect_to(oauth_slack_path(provider: 'slack'))
    end

    it 'renders no credential section for the provider that needs none' do
      get new_connection_path(provider: 'nws')

      expect(response.body).to include('connection[settings][postal_code]')
      expect(response.body).not_to include('Credentials')
    end

    it 'suggests a name so the field is never blank' do
      get new_connection_path(provider: 'github')

      expect(response.body).to include('value="GitHub"')
    end
  end

  describe 'creating and editing' do
    it 'stores settings and credentials' do
      post connections_path, params: {
        connection: { provider: 'github', label: 'Work',
                      settings: { api_endpoint: '' }, credentials: { access_token: 'ghp_abc' } }
      }

      connection = user.connections.find_by!(label: 'Work')
      expect(connection.provider).to eq('github')
      expect(connection.credential('access_token')).to eq('ghp_abc')
    end

    it 'keeps a stored credential when the field is left blank on edit' do
      connection = create(:connection, user: user, provider: 'github', label: 'Work',
                                       credentials: { 'access_token' => 'ghp_abc' })

      patch connection_path(connection), params: {
        connection: { provider: 'github', label: 'Renamed', credentials: { access_token: '' } }
      }

      expect(connection.reload.label).to eq('Renamed')
      expect(connection.credential('access_token')).to eq('ghp_abc')
    end

    it 'shows the same tailored fields when editing' do
      connection = create(:connection, user: user, provider: 'home_assistant', label: 'House')

      get edit_connection_path(connection)

      expect(response.body).to include('connection[settings][base_url]')
      expect(response.body).to include('Long-lived access token')
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings pages' do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'notification settings' do
    it 'renders every notification kind' do
      get notification_settings_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Meeting reminders', 'Breaking news', 'Connection problems')
    end

    it 'saves toggles and per-kind settings' do
      patch notification_settings_path, params: {
        notification_preferences: {
          meeting_reminder: { enabled: '1', via_web_push: '1', via_email: '0',
                              settings: { lead_minutes: '25' } }
        }
      }

      preference = user.notification_preferences.find_by(kind: 'meeting_reminder')
      expect(preference.enabled).to be(true)
      expect(preference.setting('lead_minutes')).to eq('25')
    end

    it 'turns a kind off' do
      patch notification_settings_path, params: {
        notification_preferences: { breaking_news: { enabled: '0', via_web_push: '1' } }
      }

      expect(user.notification_preferences.find_by(kind: 'breaking_news').enabled).to be(false)
    end

    # A hand-crafted post shouldn't be able to stuff arbitrary data into the
    # settings blob, or write to a kind that doesn't exist.
    it 'ignores unknown kinds and unknown setting keys' do
      patch notification_settings_path, params: {
        notification_preferences: {
          not_a_real_kind: { enabled: '1' },
          breaking_news: { enabled: '1', via_web_push: '1', settings: { evil: 'yes' } }
        }
      }

      expect(user.notification_preferences.pluck(:kind)).to eq(['breaking_news'])
      expect(user.notification_preferences.first.settings).to eq({})
    end

    it 'survives a post with nothing in it' do
      expect { patch notification_settings_path }.not_to raise_error
      expect(response).to redirect_to(notification_settings_path)
    end
  end

  describe 'api tokens' do
    it 'shows the plaintext token exactly once, then never again' do
      post api_tokens_path, params: { api_token: { name: 'Phone' } }
      follow_redirect!

      expect(response.body).to match(/smb_[A-Za-z0-9_-]+/)

      get api_tokens_path
      expect(response.body).not_to match(/smb_[A-Za-z0-9_-]+/)
    end

    it 'mints a token that actually authenticates against the API' do
      post api_tokens_path, params: { api_token: { name: 'Phone' } }
      token = flash[:token]

      get '/api/v1/dashboard', headers: { 'Authorization' => "Bearer #{token}" }

      expect(response).to have_http_status(:ok)
    end

    it 'revokes a token' do
      token = user.api_tokens.create!(name: 'Phone')

      delete api_token_path(token)

      expect(user.api_tokens.count).to be_zero
    end

    it "does not revoke somebody else's token" do
      theirs = create(:user).api_tokens.create!(name: 'Theirs')

      delete api_token_path(theirs)

      expect(response).to have_http_status(:not_found)
      expect(theirs.reload).to be_persisted
    end
  end

  describe 'todo projects' do
    it 'creates a project' do
      post todo_projects_path, params: { todo_project: { name: 'Home', color: 'emerald' } }

      expect(user.todo_projects.pluck(:name)).to eq(['Home'])
    end

    # Deleting a project must never silently delete work.
    it 'keeps the todos when a project is deleted' do
      project = create(:todo_project, user: user)
      todo = create(:todo, user: user, todo_project: project)

      delete todo_project_path(project)

      expect(todo.reload).to be_persisted
      expect(todo.todo_project_id).to be_nil
    end
  end

  describe 'api connections' do
    it 'lists connections without ever exposing credentials' do
      create(:connection, user: user, credentials: { 'password' => 'hunter2' })

      get '/api/v1/connections', headers: api_headers_for(user)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('hunter2')

      entry = response.parsed_body['connections'].first
      expect(entry).to include('provider' => 'news_feed')
      # The stored secrets never ship; only the names of what this provider needs.
      expect(entry).not_to have_key('credentials')
      expect(entry['required_credentials']).to eq(['password'])
    end

    it 'creates a connection' do
      post '/api/v1/connections',
           params: { connection: { provider: 'github', label: 'Work', credentials: { access_token: 'ghp_abc' } } },
           headers: api_headers_for(user), as: :json

      expect(response).to have_http_status(:created)
      expect(user.connections.find_by(label: 'Work').credential('access_token')).to eq('ghp_abc')
    end

    it 'keeps the stored credential when an update omits it' do
      connection = create(:connection, user: user, credentials: { 'password' => 'hunter2' })

      patch "/api/v1/connections/#{connection.id}",
            params: { connection: { label: 'Renamed' } },
            headers: api_headers_for(user), as: :json

      expect(connection.reload.label).to eq('Renamed')
      expect(connection.credential('password')).to eq('hunter2')
    end
  end
end

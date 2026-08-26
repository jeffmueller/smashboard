# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Legal pages' do
  # The whole point of these two pages: Google's OAuth consent screen requires
  # both, and a reviewer opens them from a signed-out browser. If they ever
  # start redirecting to sign-in, the consent screen configuration breaks.
  describe 'when signed out' do
    it 'serves the privacy policy' do
      get privacy_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Privacy Policy')
    end

    it 'serves the terms' do
      get terms_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Terms of Service')
    end

    it 'links them from the sign-in screen, which is where a reviewer starts' do
      get new_user_session_path

      expect(response.body).to include('href="/privacy"', 'href="/terms"')
    end
  end

  it 'names the host it applies to' do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('APP_HOST', anything).and_return('smashboard.example.com')

    get privacy_path

    expect(response.body).to include('smashboard.example.com')
  end

  describe 'the operator contact' do
    it 'is shown when one is configured' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('LEGAL_CONTACT_EMAIL', nil).and_return('ops@example.com')

      get privacy_path

      expect(response.body).to include('mailto:ops@example.com')
    end

    it 'falls back to naming the operator rather than printing a dead address' do
      get privacy_path

      expect(response.body).to include('the operator of this installation')
      expect(response.body).not_to include('mailto:')
    end
  end

  # Restricted-scope review checks for this specific commitment by name.
  it 'states Limited Use compliance for Google data' do
    get privacy_path

    expect(response.body).to include('Google API Services User Data Policy', 'Limited Use')
  end

  it 'is reachable while signed in too' do
    sign_in create(:user)

    get terms_path

    expect(response).to have_http_status(:ok)
  end
end

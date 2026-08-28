# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Dashboard' do
  let(:user) { create(:user) }

  it 'rejects a request with no token' do
    get '/api/v1/dashboard', headers: { 'Accept' => 'application/json' }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects a revoked token' do
    token = user.api_tokens.create!(name: 'spec')
    plaintext = token.plaintext_token
    token.revoke!

    get '/api/v1/dashboard', headers: { 'Authorization' => "Bearer #{plaintext}" }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns every enabled panel with its rendered data' do
    create(:countdown, user: user, name: 'Concert', target_at: 3.days.from_now)

    get '/api/v1/dashboard', headers: api_headers_for(user)

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body['panels'].pluck('kind')).to include('countdowns', 'todos', 'habits')

    countdowns = body['panels'].find { |p| p['kind'] == 'countdowns' }
    expect(countdowns.dig('data', 'countdowns').first['name']).to eq('Concert')
  end

  it 'records that the token was used' do
    token = user.api_tokens.create!(name: 'spec')

    expect do
      get '/api/v1/dashboard', headers: { 'Authorization' => "Bearer #{token.plaintext_token}" }
    end.to change { token.reload.last_used_at }.from(nil)
  end
end

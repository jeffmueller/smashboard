# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Todos' do
  let(:user) { create(:user) }
  let(:headers) { api_headers_for(user) }

  it 'lists only today\'s items when scoped' do
    create(:todo, user: user, title: 'Today', due_at: user.zone.now.end_of_day - 1.hour)
    create(:todo, user: user, title: 'Next week', due_at: 8.days.from_now)

    get '/api/v1/todos', params: { scope: 'today' }, headers: headers

    expect(response.parsed_body['todos'].pluck('title')).to eq(['Today'])
  end

  it 'completes a repeating todo and returns the closed instance' do
    todo = create(:todo, :repeating, user: user)

    expect do
      post "/api/v1/todos/#{todo.id}/complete", headers: headers, as: :json
    end.to change(Todo, :count).by(1)

    expect(response.parsed_body['completed']).to be(true)
  end

  it 'scopes to the calling user' do
    other = create(:todo, user: create(:user))

    get "/api/v1/todos/#{other.id}", headers: headers

    expect(response).to have_http_status(:not_found)
  end
end

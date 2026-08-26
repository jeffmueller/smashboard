# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Habits' do
  let(:user) { create(:user, time_zone: 'Pacific Time (US & Canada)') }
  let(:headers) { api_headers_for(user) }
  # The user's day, not the server's — see the note in Api::V1::HabitsController.
  let(:today) { user.today }

  it 'lists active habits in order' do
    create(:habit, user: user, name: 'Second', position: 1)
    create(:habit, user: user, name: 'First', position: 0)
    create(:habit, :archived, user: user, name: 'Retired')

    get '/api/v1/habits', headers: headers

    expect(response.parsed_body['habits'].pluck('name')).to eq(%w[First Second])
  end

  it 'includes archived ones on request' do
    create(:habit, :archived, user: user, name: 'Retired')

    get '/api/v1/habits', params: { scope: 'all' }, headers: headers

    expect(response.parsed_body['habits'].pluck('name')).to include('Retired')
  end

  it 'creates one at the end of the list' do
    create(:habit, user: user, position: 0)

    post '/api/v1/habits', params: { habit: { name: 'Meditate', icon: '🧘' } }, headers: headers, as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('name' => 'Meditate', 'icon' => '🧘', 'position' => 1)
  end

  it 'toggles for today and reports the streak' do
    habit = create(:habit, user: user)

    post "/api/v1/habits/#{habit.id}/toggle", headers: headers, as: :json

    expect(response.parsed_body).to include('done_today' => true, 'streak' => 1)
  end

  # So a client can fill in a day it missed without pretending to be yesterday.
  it 'accepts a date to toggle' do
    habit = create(:habit, user: user)
    yesterday = today - 1

    post "/api/v1/habits/#{habit.id}/toggle", params: { date: yesterday.iso8601 }, headers: headers, as: :json

    expect(habit.reload.completed_on?(yesterday)).to be(true)
    expect(response.parsed_body['done_today']).to be(false)
  end

  it 'falls back to today when the date is unusable' do
    habit = create(:habit, user: user)

    post "/api/v1/habits/#{habit.id}/toggle", params: { date: 'not a date' }, headers: headers, as: :json

    expect(habit.reload.completed_on?(today)).to be(true)
  end

  it 'archives without touching the completions' do
    habit = create(:habit, user: user)
    create(:habit_completion, habit: habit, completed_on: today - 1)

    post "/api/v1/habits/#{habit.id}/archive", headers: headers, as: :json

    expect(response.parsed_body).to include('archived' => true)
    expect(habit.reload).to be_archived
    expect(habit.habit_completions.count).to eq(1)
  end

  it 'drops an archived habit from the default list but keeps it under scope=all' do
    habit = create(:habit, user: user, name: 'Retired')

    post "/api/v1/habits/#{habit.id}/archive", headers: headers, as: :json
    get '/api/v1/habits', headers: headers
    expect(response.parsed_body['habits'].pluck('name')).not_to include('Retired')

    get '/api/v1/habits', params: { scope: 'all' }, headers: headers
    expect(response.parsed_body['habits'].pluck('name')).to include('Retired')
  end

  it 'unarchives' do
    habit = create(:habit, :archived, user: user)

    post "/api/v1/habits/#{habit.id}/unarchive", headers: headers, as: :json

    expect(response.parsed_body).to include('archived' => false)
    expect(habit.reload).not_to be_archived
  end

  it 'does not archive a habit belonging to somebody else' do
    theirs = create(:habit, user: create(:user))

    post "/api/v1/habits/#{theirs.id}/archive", headers: headers, as: :json

    expect(response).to have_http_status(:not_found)
    expect(theirs.reload).not_to be_archived
  end

  # The API base controller inherits ActionController::API, so it gets none of
  # ApplicationController's around_action that puts a request in the user's
  # zone. Without an explicit user-zone lookup, a Pacific user checking in
  # during their evening marks the *next* day done. 02:00 UTC is 19:00 the
  # previous day in PDT, so the two dates genuinely differ here.
  it 'records the completion on the user day, not the server day' do
    habit = create(:habit, user: user)
    travel_to(Time.utc(2026, 3, 10, 2, 0, 0)) do
      post "/api/v1/habits/#{habit.id}/toggle", headers: headers, as: :json

      expect(habit.reload.completed_on?(Date.new(2026, 3, 9))).to be(true)
      expect(habit.completed_on?(Date.new(2026, 3, 10))).to be(false)
      expect(response.parsed_body['done_today']).to be(true)
    end
  end

  it 'reorders' do
    a = create(:habit, user: user, position: 0)
    b = create(:habit, user: user, position: 1)

    post '/api/v1/habits/reorder', params: { habit_ids: [b.id, a.id] }, headers: headers, as: :json

    expect(user.habits.ordered.pluck(:id)).to eq([b.id, a.id])
  end

  it 'scopes to the calling user' do
    theirs = create(:habit, user: create(:user))

    get "/api/v1/habits/#{theirs.id}", headers: headers

    expect(response).to have_http_status(:not_found)
  end

  it 'requires a token' do
    get '/api/v1/habits'

    expect(response).to have_http_status(:unauthorized)
  end
end

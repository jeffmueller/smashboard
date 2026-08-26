# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Signed-out screens' do
  # They get their own centred layout rather than dashboard chrome, which has
  # nothing to show without a user.
  it 'renders sign in on the auth layout' do
    get new_user_session_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Sign in', 'smashboard')
    expect(response.body).not_to include('Countdowns</a>')
  end

  it 'renders sign up with the fields the account needs' do
    get new_user_registration_path

    expect(response.body).to include('user[first_name]', 'user[last_name]', 'user[time_zone]')
  end

  it 'renders the password reset request' do
    get new_user_password_path

    expect(response.body).to include('Reset your password')
  end

  it 'renders the password reset form' do
    get edit_user_password_path(reset_password_token: 'token')

    expect(response.body).to include('Choose a new password')
  end

  it 'carries theme tokens rather than hardcoded colours' do
    get new_user_session_path

    expect(response.body).to include('bg-canvas')
    expect(response.body).not_to match(/bg-slate-\d/)
  end

  it 'creates an account with a first and last name' do
    post user_registration_path, params: {
      user: { first_name: 'Dana', last_name: 'Lee', email: 'dana@example.com',
              time_zone: 'Eastern Time (US & Canada)',
              password: 'password123', password_confirmation: 'password123' }
    }

    user = User.find_by(email: 'dana@example.com')
    expect(user.first_name).to eq('Dana')
    expect(user.display_name).to eq('Dana')
    expect(user.time_zone).to eq('Eastern Time (US & Canada)')
  end
end

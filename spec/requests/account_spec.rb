# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Account' do
  let(:user) { create(:user, first_name: 'Alex', last_name: 'Rivera', password: 'password123') }

  before { sign_in user }

  it 'shows the current details' do
    get account_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Alex', 'Rivera', user.email)
  end

  describe 'profile' do
    it 'saves name, zone and postal code without asking for a password' do
      patch account_path, params: {
        user: { first_name: 'Robin', last_name: 'Vega',
                time_zone: 'Pacific Time (US & Canada)', postal_code: '90210' }
      }

      user.reload
      expect(user.first_name).to eq('Robin')
      expect(user.time_zone).to eq('Pacific Time (US & Canada)')
      expect(user.postal_code).to eq('90210')
    end

    it 'rejects a time zone that is not real' do
      patch account_path, params: { user: { time_zone: 'Middle Earth' } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.time_zone).not_to eq('Middle Earth')
    end

    # Profile fields must not be a back door to changing the password.
    it 'ignores a password submitted through the profile form' do
      patch account_path, params: { user: { first_name: 'Robin', password: 'hacked-password' } }

      expect(user.reload.valid_password?('password123')).to be(true)
    end
  end

  describe 'email and password' do
    it 'changes the password when the current one is given' do
      patch password_account_path, params: {
        user: { password: 'a-new-password', password_confirmation: 'a-new-password',
                current_password: 'password123' }
      }

      expect(user.reload.valid_password?('a-new-password')).to be(true)
    end

    # Devise rotates the session on a password change; being signed out for
    # succeeding would be a strange reward.
    it 'keeps the user signed in afterwards' do
      patch password_account_path, params: {
        user: { password: 'a-new-password', password_confirmation: 'a-new-password',
                current_password: 'password123' }
      }
      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Account')
    end

    it 'refuses without the current password' do
      patch password_account_path, params: {
        user: { password: 'a-new-password', password_confirmation: 'a-new-password',
                current_password: 'wrong' }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.valid_password?('password123')).to be(true)
    end

    it 'changes the email with the current password and no new password' do
      patch password_account_path, params: {
        user: { email: 'moved@example.com', current_password: 'password123' }
      }

      expect(user.reload.email).to eq('moved@example.com')
    end

    it 'refuses a mismatched confirmation' do
      patch password_account_path, params: {
        user: { password: 'a-new-password', password_confirmation: 'different',
                current_password: 'password123' }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.valid_password?('password123')).to be(true)
    end
  end

  it "sends Devise's own account editor here instead" do
    get '/users/edit'

    expect(response).to redirect_to(account_path)
  end
end

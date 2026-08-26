# frozen_string_literal: true

class AccountsController < ApplicationController
  before_action :load_user

  def show; end

  # Name, zone and postal code carry no security weight, so they save without a
  # password challenge.
  def update
    if @user.update(profile_params)
      redirect_to account_path, notice: 'Profile saved.'
    else
      render :show, status: :unprocessable_content
    end
  end

  # Email and password both do carry weight, so Devise's update_with_password
  # requires the current one. Blank password fields mean "email only".
  def password
    if @user.update_with_password(security_params)
      # Changing a password rotates the session, so re-sign the user in rather
      # than bouncing them to the login screen for succeeding.
      bypass_sign_in(@user, scope: :user)
      redirect_to account_path, notice: 'Account updated.'
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  def load_user
    @user = current_user
  end

  def profile_params
    params.expect(user: %i[first_name last_name time_zone postal_code])
  end

  def security_params
    params.expect(user: %i[email password password_confirmation current_password])
          .compact_blank
  end
end

# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import
  # maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Signed-out screens get a focused, centred layout rather than the dashboard
  # chrome, which has nothing to show without a user.
  layout :layout_for_request

  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?

  around_action :use_user_time_zone, if: :user_signed_in?

  private

  def layout_for_request
    devise_controller? ? 'auth' : 'application'
  end

  # Ownership throughout this app is enforced by scoping every query through
  # current_user's associations, so a record from another account is a 404
  # rather than a policy failure.
  def use_user_time_zone(&)
    Time.use_zone(current_user.zone, &)
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: %i[first_name last_name time_zone postal_code])
    devise_parameter_sanitizer.permit(:account_update, keys: %i[first_name last_name time_zone postal_code])
  end
end

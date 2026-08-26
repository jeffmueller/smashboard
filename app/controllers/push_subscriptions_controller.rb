# frozen_string_literal: true

# Registration endpoint for the PWA service worker's Web Push subscription.
class PushSubscriptionsController < ApplicationController
  skip_forgery_protection only: :create

  def create
    subscription = current_user.push_subscriptions.find_or_initialize_by(endpoint: params.require(:endpoint))
    subscription.assign_attributes(
      p256dh_key: params.require(:keys)[:p256dh],
      auth_key: params.require(:keys)[:auth],
      user_agent: request.user_agent,
      last_used_at: Time.current
    )

    if subscription.save
      head :created
    else
      head :unprocessable_content
    end
  rescue ActionController::ParameterMissing
    head :bad_request
  end

  def destroy
    current_user.push_subscriptions.find_by(endpoint: params[:endpoint])&.destroy
    head :no_content
  end
end

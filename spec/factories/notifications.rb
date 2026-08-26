# frozen_string_literal: true

FactoryBot.define do
  factory :push_subscription do
    user
    sequence(:endpoint) { |n| "https://push.example.com/endpoint-#{n}" }
    p256dh_key { 'p256dh-key' }
    auth_key { 'auth-key' }
  end

  factory :notification_preference do
    user
    kind { 'breaking_news' }
    enabled { true }
    via_web_push { true }
    via_email { false }
  end
end

# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { 'password123' }
    first_name { 'Test' }
    last_name { 'User' }
    time_zone { 'Eastern Time (US & Canada)' }
  end
end

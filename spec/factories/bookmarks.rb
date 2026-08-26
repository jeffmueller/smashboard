# frozen_string_literal: true

FactoryBot.define do
  factory :bookmark do
    user
    title { 'GitHub' }
    sequence(:url) { |n| "https://example#{n}.com" }
  end
end

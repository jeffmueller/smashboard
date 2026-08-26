# frozen_string_literal: true

FactoryBot.define do
  factory :panel do
    user
    kind { 'clock' }
    position { 0 }
  end
end

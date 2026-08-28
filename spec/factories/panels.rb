# frozen_string_literal: true

FactoryBot.define do
  factory :panel do
    user
    kind { 'countdowns' }
    position { 0 }
  end
end

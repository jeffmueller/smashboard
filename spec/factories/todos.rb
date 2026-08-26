# frozen_string_literal: true

FactoryBot.define do
  factory :todo_project do
    user
    name { 'Home' }
  end

  factory :todo do
    user
    title { 'Take the bins out' }

    trait :repeating do
      rrule { 'FREQ=DAILY' }
      due_at { 1.hour.from_now }
    end
  end
end

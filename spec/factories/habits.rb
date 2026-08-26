# frozen_string_literal: true

FactoryBot.define do
  factory :habit do
    user
    sequence(:name) { |n| "Habit #{n}" }

    trait :archived do
      archived_at { Time.current }
    end
  end

  factory :habit_completion do
    habit
    completed_on { Time.zone.today }
  end
end

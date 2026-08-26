# frozen_string_literal: true

FactoryBot.define do
  factory :countdown do
    user
    name { 'Concert' }
    color { 'sky' }
    target_at { 3.days.from_now }

    trait :recurring do
      target_at { nil }
      rrule { 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR' }
      starts_on { Date.current }
      occurs_at_time { Time.zone.parse('15:10') }
    end
  end
end

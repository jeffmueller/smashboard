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
      # In the user's zone, not the ambient one. `occurs_at_time` is a `time`
      # column that Active Record stores as an instant, so writing it under the
      # suite's UTC would mean 15:10 UTC — 11:10 for an Eastern user, and not
      # the time this fixture reads as saying.
      occurs_at_time { user.zone.parse('15:10') }
    end
  end
end

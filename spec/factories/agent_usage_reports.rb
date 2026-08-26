# frozen_string_literal: true

FactoryBot.define do
  factory :agent_usage_report do
    user
    agent { 'claude' }
    sequence(:machine) { |n| "laptop-#{n}" }
    reported_at { Time.current }
    payload do
      {
        'ready' => true,
        'tierLabel' => 'Max 5x',
        'limits' => [
          { 'label' => 'Session (5-hour)', 'percent' => 0.23, 'resetsAt' => 2.hours.from_now.iso8601 },
          { 'label' => 'Weekly (7-day)', 'percent' => 0.17, 'resetsAt' => 3.days.from_now.iso8601 }
        ],
        'todayTotalTokens' => 1_000,
        'todayTokensByModel' => { 'claude-opus-5' => 1_000 },
        'todayPrompts' => 40,
        'todaySessions' => 2,
        'recentDays' => [
          { 'date' => 2.days.ago.to_date.iso8601, 'messageCount' => 400 },
          { 'date' => 1.day.ago.to_date.iso8601, 'messageCount' => 700 },
          { 'date' => Time.zone.today.iso8601, 'messageCount' => 1_000 }
        ]
      }
    end
  end
end

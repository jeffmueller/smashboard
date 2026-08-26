# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NotifyUpcomingMeetingsJob do
  let(:user) { create(:user) }
  let(:panel) { user.panels.find_by!(kind: 'calendar') }
  let(:now) { Time.utc(2026, 8, 25, 14) }
  # Without a registered device there is nothing to deliver to, which would
  # make every "stays quiet" expectation below pass for the wrong reason.
  let!(:device) { create(:push_subscription, user: user) }

  def event(minutes_out, overrides = {})
    starts_at = now + minutes_out.minutes
    {
      'uid' => "evt-#{minutes_out}", 'title' => 'Design Review',
      'starts_at' => starts_at.iso8601, 'ends_at' => (starts_at + 1.hour).iso8601,
      'all_day' => false, 'video_url' => nil, 'video_provider' => nil
    }.merge(overrides)
  end

  def cache(events)
    panel.update!(data: { 'events' => events }, data_status: 'ok', data_fetched_at: now)
  end

  before do
    travel_to(now)
    capture_pushes
  end

  it 'reminds about a meeting inside the lead time' do
    cache([event(5)])

    described_class.perform_now

    expect(sent_pushes.size).to eq(1)
    expect(JSON.parse(sent_pushes.first[:message])).to include('title' => 'Design Review',
                                                               'body' => 'in 5 minutes')
  end

  it 'stays quiet about a meeting still beyond the lead time' do
    cache([event(45)])

    described_class.perform_now

    expect(sent_pushes).to be_empty
  end

  it 'honours a custom lead time' do
    create(:notification_preference, user: user, kind: 'meeting_reminder', settings: { 'lead_minutes' => 60 })
    cache([event(45)])

    described_class.perform_now

    expect(sent_pushes.size).to eq(1)
  end

  it 'never reminds twice about the same meeting' do
    cache([event(5)])

    3.times { described_class.perform_now }

    expect(sent_pushes.size).to eq(1)
  end

  it 'ignores meetings already under way' do
    cache([event(-5)])

    described_class.perform_now

    expect(sent_pushes).to be_empty
  end

  it 'ignores all-day events' do
    cache([event(5, 'all_day' => true)])

    described_class.perform_now

    expect(sent_pushes).to be_empty
  end

  it 'points the notification at the video call when there is one' do
    cache([event(5, 'video_url' => 'https://meet.google.com/abc-defg-hij', 'video_provider' => 'Google Meet')])

    described_class.perform_now

    message = JSON.parse(sent_pushes.first[:message])
    expect(message['url']).to eq('https://meet.google.com/abc-defg-hij')
    expect(message['body']).to include('tap to join Google Meet')
  end

  it 'says "starting now" for a meeting about to begin' do
    cache([event(1)])

    described_class.perform_now

    expect(JSON.parse(sent_pushes.first[:message])['body']).to eq('starting now')
  end

  it 'stays quiet when the user turned meeting reminders off' do
    create(:notification_preference, user: user, kind: 'meeting_reminder', enabled: false)
    cache([event(5)])

    described_class.perform_now

    expect(sent_pushes).to be_empty
  end

  it 'survives a panel with malformed cached data' do
    panel.update!(data: { 'events' => [{ 'uid' => 'x', 'starts_at' => 'not a time' }] })

    expect { described_class.perform_now }.not_to raise_error
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Meetings::IcsParser do
  let(:ics) { Rails.root.join('spec/fixtures/calendars/today.ics').read }
  let(:events) { described_class.parse(ics, calendar_name: 'Work', user_email: 'alex@example.com') }

  def event(title)
    events.find { |e| e[:title] == title }
  end

  it 'drops cancelled events' do
    expect(events.pluck(:title)).not_to include('Called Off')
  end

  it 'drops events the user declined' do
    expect(events.pluck(:title)).not_to include('Optional Sync')
  end

  it 'keeps a declined event when it belongs to somebody else' do
    others = described_class.parse(ics, calendar_name: 'Work', user_email: 'someone@example.com')

    expect(others.pluck(:title)).to include('Optional Sync')
  end

  it 'converts a zoned start into UTC' do
    # 09:30 America/New_York in August is UTC-4.
    expect(event('Daily Standup')[:starts_at]).to eq(Time.utc(2026, 8, 25, 13, 30))
  end

  it 'marks all-day events and spans them to the next day' do
    holiday = event('Company Holiday')

    expect(holiday[:all_day]).to be(true)
    expect(holiday[:ends_at] - holiday[:starts_at]).to eq(1.day)
  end

  it 'pulls a Zoom link out of the location' do
    standup = event('Daily Standup')

    expect(standup[:video_url]).to eq('https://acme.zoom.us/j/98765432101?pwd=abcDEF')
    expect(standup[:video_provider]).to eq('Zoom')
  end

  it 'blanks a location that is only the video URL' do
    expect(event('Daily Standup')[:location]).to be_nil
  end

  it 'keeps a real location alongside a video link' do
    review = event('Design Review')

    expect(review[:location]).to eq('Room 4B')
    expect(review[:video_provider]).to eq('Google Meet')
  end

  it 'reads the Meet link from X-GOOGLE-CONFERENCE, not the description decoy' do
    expect(event('Design Review')[:video_url]).to eq('https://meet.google.com/abc-defg-hij')
  end

  it 'reads the organizer common name' do
    expect(event('Daily Standup')[:organizer]).to eq('Dana Lee')
  end

  it 'gives an untitled event a placeholder' do
    expect(events.pluck(:title)).to include('(no title)')
  end

  it 'returns an empty list rather than raising on junk input' do
    expect(described_class.parse('this is not a calendar', calendar_name: 'Work')).to eq([])
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NotifyCountdownsJob do
  let(:user) { create(:user) }
  let(:now) { Time.utc(2026, 8, 25, 14) }

  # Without a registered device there is nothing to deliver to, which would make
  # every "stays quiet" expectation below pass for the wrong reason.
  let!(:device) { create(:push_subscription, user: user) }

  # before/after rather than an `around` block so individual examples can travel
  # again without nesting travel_to, which ActiveSupport rejects.
  before do
    travel_to(now)
    capture_pushes
  end

  # The job runs every minute and fires on the first tick at or after the
  # moment, so "reached" means the moment is now behind us.
  it 'fires once a countdown has reached its moment' do
    create(:countdown, user: user, name: 'Kid one home', target_at: now - 30.seconds)

    described_class.perform_now

    expect(sent_pushes.size).to eq(1)
    expect(JSON.parse(sent_pushes.first[:message])).to include('title' => 'Kid one home', 'body' => 'Now')
  end

  it 'stays quiet while a countdown is still running' do
    create(:countdown, user: user, target_at: now + 3.hours)

    described_class.perform_now

    expect(sent_pushes).to be_empty
  end

  # A countdown that came due between two runs must not be skipped for having
  # already passed by the time anything looked.
  it 'still fires for a moment that passed within the grace window' do
    create(:countdown, user: user, target_at: now - 90.seconds)

    described_class.perform_now

    expect(sent_pushes.size).to eq(1)
  end

  it 'gives up on a moment older than the grace window' do
    create(:countdown, user: user, target_at: now - 10.minutes)

    described_class.perform_now

    expect(sent_pushes).to be_empty
  end

  it 'warns ahead of time when a lead time is set' do
    create(:notification_preference, user: user, kind: 'countdown_reached', settings: { 'lead_minutes' => 15 })
    create(:countdown, user: user, name: 'Kid two home', target_at: now + 10.minutes)

    described_class.perform_now

    expect(JSON.parse(sent_pushes.first[:message])['body']).to eq('in 10 minutes')
  end

  it 'never fires twice for the same occurrence' do
    create(:countdown, user: user, target_at: now - 30.seconds)

    3.times { described_class.perform_now }

    expect(sent_pushes.size).to eq(1)
  end

  it 'fires again on the next occurrence of a recurring countdown' do
    countdown = create(:countdown, :recurring, user: user, occurs_at_time: Time.zone.parse('15:10'))
    first = countdown.next_occurrence_at

    travel_to(first + 10.seconds)
    described_class.perform_now

    second = countdown.reload.next_occurrence_at
    travel_to(second + 10.seconds)
    described_class.perform_now

    expect(second).to be > first
    expect(sent_pushes.size).to eq(2)
  end

  it 'ignores a dismissed occurrence' do
    countdown = create(:countdown, user: user, target_at: now - 30.seconds)
    countdown.dismiss!(countdown.upcoming_occurrences(from: now - 2.minutes).first)

    described_class.perform_now

    expect(sent_pushes).to be_empty
  end

  it 'ignores a disabled countdown' do
    create(:countdown, user: user, target_at: now - 30.seconds, enabled: false)

    described_class.perform_now

    expect(sent_pushes).to be_empty
  end

  it 'stays quiet when the user turned countdown alerts off' do
    create(:notification_preference, user: user, kind: 'countdown_reached', enabled: false)
    create(:countdown, user: user, target_at: now - 30.seconds)

    described_class.perform_now

    expect(sent_pushes).to be_empty
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CountdownsPanel do
  let(:user) { create(:user) }
  let(:panel) { create(:panel, user: user, kind: 'countdowns') }

  it 'is a local panel that needs no connection' do
    expect(described_class).not_to be_remote
    expect(panel.presenter).to be_configured
  end

  it 'orders countdowns by how soon they land, not by position' do
    create(:countdown, user: user, name: 'Later', target_at: 5.days.from_now, position: 0)
    create(:countdown, user: user, name: 'Sooner', target_at: 2.hours.from_now, position: 1)

    names = panel.presenter.build[:countdowns].pluck(:name)

    expect(names).to eq(%w[Sooner Later])
  end

  it 'drops countdowns with nothing upcoming' do
    expired = build(:countdown, user: user, target_at: 1.day.ago)
    expired.save!(validate: false)

    expect(panel.presenter.build[:countdowns]).to be_empty
  end

  # Pinned to a weekday morning: the recurring factory lands at 15:10 on
  # weekdays, and a recurring countdown is only on the board on its own day, so
  # an unpinned run would fail every evening and all weekend.
  it 'flags whether a dismissal is permanent' do
    travel_to(Time.zone.local(2026, 8, 27, 9, 0, 0)) do
      create(:countdown, :recurring, user: user, name: 'School')
      create(:countdown, user: user, name: 'Concert', target_at: 10.days.from_now)

      entries = panel.presenter.build[:countdowns].index_by { |c| c[:name] }

      expect(entries['School'][:returns_after_dismissal]).to be(true)
      expect(entries['Concert'][:returns_after_dismissal]).to be(false)
    end
  end

  describe 'a recurring countdown only appears on its own day' do
    # Daily at 08:00, so "later today" and "tomorrow" are both reachable just by
    # moving the clock either side of it.
    def daily_at_eight(**attrs)
      create(:countdown, user: user, name: 'School run', target_at: nil,
                         rrule: 'FREQ=DAILY', starts_on: Date.new(2026, 8, 1),
                         occurs_at_time: user.zone.parse('08:00'), **attrs)
    end

    # Every clock reading below is in the *user's* zone, because that is the zone
    # the rule judges in. Writing them in the server's UTC instead reads as
    # though it were the same thing, and it isn't — 00:00 UTC is still the
    # previous evening in Eastern.
    def at(...)
      user.zone.local(...)
    end

    def names(now)
      travel_to(now) { panel.presenter.build[:countdowns].pluck(:name) }
    end

    it 'shows it on the morning it happens' do
      daily_at_eight

      expect(names(at(2026, 8, 27, 6, 0, 0))).to include('School run')
    end

    it 'holds it back once the next run is tomorrow' do
      daily_at_eight

      expect(names(at(2026, 8, 27, 20, 0, 0))).to be_empty
    end

    it 'brings it back at midnight' do
      daily_at_eight

      expect(names(at(2026, 8, 27, 23, 59, 59))).to be_empty
      expect(names(at(2026, 8, 28, 0, 0, 1))).to include('School run')
    end

    # The whole point of a one-off is watching it approach.
    it 'never holds back a one-off, however far out' do
      create(:countdown, user: user, name: 'Concert', target_at: at(2026, 11, 2, 19, 0, 0))

      expect(names(at(2026, 8, 27, 20, 0, 0))).to include('Concert')
    end

    # 2026-08-27 04:00 UTC is still the 26th in Pacific, so the next 09:00
    # Pacific run is tomorrow *there* and today in UTC. Judging in the server's
    # zone would leave it on the board a day early.
    it "judges the day in the countdown's own zone, not the server's" do
      create(:countdown, user: user, name: 'Pacific standup', target_at: nil,
                         rrule: 'FREQ=DAILY', starts_on: Date.new(2026, 8, 1),
                         occurs_at_time: ActiveSupport::TimeZone['Pacific Time (US & Canada)'].parse('09:00'),
                         time_zone: 'Pacific Time (US & Canada)')

      expect(names(Time.utc(2026, 8, 27, 4, 0, 0))).to be_empty
    end
  end

  it 'omits a dismissed occurrence' do
    countdown = create(:countdown, user: user, target_at: 4.hours.from_now)
    countdown.dismiss!(countdown.next_occurrence_at)

    expect(panel.presenter.build[:countdowns]).to be_empty
  end
end

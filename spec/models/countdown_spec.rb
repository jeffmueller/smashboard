# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Countdown do
  let(:user) { create(:user, time_zone: 'Eastern Time (US & Canada)') }

  describe 'validations' do
    it { is_expected.to belong_to(:user) }

    it 'rejects a countdown with neither a target nor a recurrence' do
      countdown = build(:countdown, target_at: nil, rrule: nil)

      expect(countdown).not_to be_valid
      expect(countdown.errors[:base]).to include('needs either a target date or a recurrence rule')
    end

    it 'rejects an unparseable recurrence rule' do
      countdown = build(:countdown, :recurring, rrule: 'NOT-AN-RRULE')

      expect(countdown).not_to be_valid
      expect(countdown.errors[:rrule]).to be_present
    end
  end

  describe '#next_occurrence_at' do
    it 'returns the target for a future one-off' do
      target = 3.days.from_now.change(usec: 0)
      countdown = create(:countdown, user: user, target_at: target)

      expect(countdown.next_occurrence_at).to be_within(1.second).of(target)
    end

    it 'returns nil once a one-off has passed' do
      countdown = build(:countdown, user: user, target_at: 1.day.ago)
      countdown.save!(validate: false)

      expect(countdown.next_occurrence_at).to be_nil
    end

    it 'lands on the configured time of day in the user zone' do
      countdown = create(:countdown, :recurring, user: user, occurs_at_time: Time.zone.parse('15:10'))

      occurrence = countdown.next_occurrence_at.in_time_zone(user.zone)

      expect(occurrence.hour).to eq(15)
      expect(occurrence.min).to eq(10)
    end

    it 'only produces weekdays for a weekday rule' do
      countdown = create(:countdown, :recurring, user: user)

      occurrences = countdown.upcoming_occurrences(limit: 10)

      expect(occurrences).to all(satisfy { |at| (1..5).cover?(at.in_time_zone(user.zone).wday) })
    end
  end

  describe 'dismissal' do
    let(:countdown) { create(:countdown, :recurring, user: user) }

    it 'skips only the dismissed occurrence and rolls on to the next' do
      first = countdown.next_occurrence_at
      countdown.dismiss!(first)

      second = countdown.reload.next_occurrence_at

      expect(second).to be > first
      expect(countdown.dismissed?(first)).to be(true)
      expect(countdown.dismissed?(second)).to be(false)
    end

    it 'keeps skipping as successive occurrences are dismissed' do
      3.times { countdown.reload.dismiss!(countdown.next_occurrence_at) }

      expect(countdown.reload.dismissals.count).to eq(3)
      expect(countdown.next_occurrence_at).to be_present
    end

    it 'is idempotent for the same occurrence' do
      occurrence = countdown.next_occurrence_at

      countdown.dismiss!(occurrence)
      expect { countdown.reload.dismiss!(occurrence) }.not_to change(CountdownDismissal, :count)
    end

    it 'silences a one-off permanently' do
      one_off = create(:countdown, user: user, target_at: 2.days.from_now)
      one_off.dismiss!(one_off.next_occurrence_at)

      expect(one_off.reload.next_occurrence_at).to be_nil
    end
  end

  describe '#seconds_remaining' do
    it 'counts down to the next occurrence' do
      countdown = create(:countdown, user: user, target_at: 90.minutes.from_now)

      expect(countdown.seconds_remaining).to be_within(2).of(5400)
    end

    it 'is nil when nothing is upcoming' do
      countdown = build(:countdown, user: user, target_at: 1.day.ago)
      countdown.save!(validate: false)

      expect(countdown.seconds_remaining).to be_nil
    end
  end
end

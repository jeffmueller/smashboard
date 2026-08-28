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
      countdown = create(:countdown, :recurring, user: user, occurs_at_time: user.zone.parse('15:10'))

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

  # `occurs_at_time` is a `time` column that Active Record stores as an instant:
  # the form runs inside the user's zone, so 2:20pm is written as 19:20 UTC.
  # Reading it back in the ambient zone made a request and a job disagree by the
  # offset; reading it in UTC shifted every countdown by the offset instead. It
  # has to be read in the countdown's own zone, which is where the schedule is
  # built.
  describe 'the time of day a recurring countdown is scheduled for' do
    # Exactly how the form writes it: inside a request, in the user's zone.
    def as_typed_in_the_form(time)
      Time.use_zone(user.zone) do
        create(:countdown, user: user, target_at: nil, rrule: 'FREQ=DAILY',
                           starts_on: Date.new(2026, 8, 1), occurs_at_time: time)
      end
    end

    it 'schedules for the time the user actually typed' do
      countdown = as_typed_in_the_form('14:20')

      at = countdown.next_occurrence_at(from: Time.utc(2026, 8, 28, 6, 0, 0))

      expect(at.in_time_zone(user.zone).strftime('%H:%M')).to eq('14:20')
    end

    it 'reads the same whoever is asking' do
      countdown = as_typed_in_the_form('14:20')
      from = Time.utc(2026, 8, 28, 6, 0, 0)

      occurrences = ['UTC', 'Eastern Time (US & Canada)', 'Australia/Sydney'].map do |ambient|
        Time.use_zone(ambient) { described_class.find(countdown.id).next_occurrence_at(from: from) }
      end

      expect(occurrences.uniq.size).to eq(1)
    end

    # The board renders in a request and the notifier runs in a job. They read
    # the same row and must land on the same instant.
    it 'agrees between a request and a job' do
      countdown = as_typed_in_the_form('14:20')
      from = Time.utc(2026, 8, 28, 6, 0, 0)

      in_a_job = described_class.find(countdown.id).next_occurrence_at(from: from)
      in_a_request = Time.use_zone(user.zone) do
        described_class.find(countdown.id).next_occurrence_at(from: from)
      end

      expect(in_a_request).to eq(in_a_job)
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

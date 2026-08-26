# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Meetings::RecurrenceExpander do
  def event(overrides = {})
    {
      uid: 'standup',
      title: 'Standup',
      starts_at: Time.utc(2026, 8, 24, 13, 30),
      ends_at: Time.utc(2026, 8, 24, 13, 45),
      rrule: 'FREQ=DAILY',
      exdates: []
    }.merge(overrides)
  end

  let(:from) { Time.utc(2026, 8, 24) }
  let(:to) { Time.utc(2026, 8, 28) }

  it 'leaves non-recurring events alone' do
    single = event(rrule: nil)

    expect(described_class.expand([single], from: from, to: to)).to eq([single])
  end

  it 'produces one entry per occurrence in the window' do
    occurrences = described_class.expand([event], from: from, to: to)

    expect(occurrences.size).to eq(4)
    expect(occurrences.map { |o| o[:starts_at].to_date.day }).to eq([24, 25, 26, 27])
  end

  it 'preserves the duration of each occurrence' do
    occurrences = described_class.expand([event], from: from, to: to)

    expect(occurrences).to all(satisfy { |o| o[:ends_at] - o[:starts_at] == 15.minutes })
  end

  it 'gives each occurrence a distinct uid' do
    uids = described_class.expand([event], from: from, to: to).pluck(:uid)

    expect(uids.uniq.size).to eq(uids.size)
  end

  it 'honours EXDATE cancellations' do
    with_exception = event(exdates: [Time.utc(2026, 8, 26, 13, 30)])

    days = described_class.expand([with_exception], from: from, to: to).map { |o| o[:starts_at].to_date.day }

    expect(days).to eq([24, 25, 27])
  end

  it 'drops events that fall outside the window' do
    past = event(rrule: nil, starts_at: Time.utc(2026, 8, 1), ends_at: Time.utc(2026, 8, 1, 1))

    expect(described_class.expand([past], from: from, to: to)).to be_empty
  end

  it 'keeps an event that straddles the window start' do
    straddling = event(rrule: nil, starts_at: from - 30.minutes, ends_at: from + 30.minutes)

    expect(described_class.expand([straddling], from: from, to: to)).to eq([straddling])
  end

  it 'falls back to the unexpanded event when the rule is unparseable' do
    broken = event(rrule: 'NONSENSE')

    expect(described_class.expand([broken], from: from, to: to)).to eq([broken])
  end
end

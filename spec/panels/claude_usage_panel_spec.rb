# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaudeUsagePanel do
  let(:user) { create(:user) }
  let(:panel) { user.panels.find_by(kind: 'claude_usage') }

  it 'is a local panel — the data is pushed to it, never fetched' do
    expect(described_class.remote?).to be(false)
    expect(described_class.required_providers).to be_empty
  end

  it 'says nothing has reported yet when no machine has' do
    data = described_class.new(panel).build

    expect(data[:machines]).to be_empty
    expect(data[:message]).to include('No machine has reported')
  end

  it 'reports the limits and the plan from a machine' do
    create(:agent_usage_report, user: user, machine: 'laptop')

    data = described_class.new(panel).build

    expect(data[:tier]).to eq('Max 5x')
    expect(data[:limits].pluck(:label)).to eq(['Session (5-hour)', 'Weekly (7-day)'])
    expect(data[:limits].first[:percent]).to be_within(0.001).of(0.23)
    expect(data[:limits].first[:resets_label]).to include('resets in')
  end

  it 'sums token counts across machines' do
    create(:agent_usage_report, user: user, machine: 'laptop')
    create(:agent_usage_report, user: user, machine: 'desktop')

    data = described_class.new(panel).build

    expect(data[:today_tokens]).to eq(2_000)
    expect(data[:today_by_model]).to eq([{ model: 'claude-opus-5', tokens: 2_000 }])
    expect(data[:machines].pluck(:name)).to contain_exactly('laptop', 'desktop')
  end

  # Rate limits are a property of the account, not the machine, so summing them
  # would produce a number over 100% as soon as a second machine reported.
  it 'takes limits from one machine rather than adding them up' do
    create(:agent_usage_report, user: user, machine: 'laptop')
    create(:agent_usage_report, user: user, machine: 'desktop')

    expect(described_class.new(panel).build[:limits].first[:percent]).to be_within(0.001).of(0.23)
  end

  it 'prefers a fresh machine over a stale one for the limits' do
    create(:agent_usage_report, user: user, machine: 'asleep', reported_at: 3.hours.ago,
                                payload: { 'tierLabel' => 'Stale plan', 'limits' => [] })
    create(:agent_usage_report, user: user, machine: 'awake')

    expect(described_class.new(panel).build[:tier]).to eq('Max 5x')
  end

  it 'marks a machine that has stopped reporting as stale' do
    create(:agent_usage_report, user: user, machine: 'asleep', reported_at: 3.hours.ago)

    data = described_class.new(panel).build

    expect(data[:machines].first[:stale]).to be(true)
    expect(data[:stale]).to be(true)
  end

  # The collector's recentDays carries a token total under `messageCount`.
  it 'reads daily totals oldest first' do
    create(:agent_usage_report, user: user, machine: 'laptop')

    days = described_class.new(panel).build[:recent_days]

    expect(days.pluck(:tokens)).to eq([400, 700, 1_000])
    expect(days.first[:date]).to be < days.last[:date]
  end

  it 'does not leak another user\'s machines' do
    create(:agent_usage_report, user: create(:user), machine: 'theirs')

    expect(described_class.new(panel).build[:machines]).to be_empty
  end
end

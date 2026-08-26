# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HabitsPanel do
  let(:user) { create(:user, time_zone: 'Pacific Time (US & Canada)') }
  let(:panel) { user.panels.find_by(kind: 'habits') }

  def build_data = described_class.new(panel).build

  it 'is a local panel' do
    expect(described_class.remote?).to be(false)
    expect(described_class.required_providers).to be_empty
  end

  it 'shows nothing to a user with no habits' do
    data = build_data

    expect(data[:habits]).to be_empty
    expect(data[:activity][:weeks]).to be_empty.or be_present
  end

  describe 'today' do
    let!(:meds) { create(:habit, user: user, name: 'Take meds', icon: '💊', position: 0) }
    let!(:run) { create(:habit, user: user, name: 'Exercise', position: 1) }

    it 'lists habits in order with their icons' do
      data = build_data

      expect(data[:habits].pluck(:name)).to eq(['Take meds', 'Exercise'])
      expect(data[:habits].first).to include(icon: '💊', initial: 'T')
      expect(data[:habits].second[:icon]).to be_nil
    end

    it 'marks what is done and counts it' do
      meds.complete!(Time.current.in_time_zone(user.zone).to_date)

      data = build_data

      expect(data[:habits].find { |h| h[:name] == 'Take meds' }[:done]).to be(true)
      expect(data[:habits].find { |h| h[:name] == 'Exercise' }[:done]).to be(false)
      expect(data).to include(done_count: 1, total_count: 2)
    end

    it 'leaves archived habits out' do
      create(:habit, :archived, user: user, name: 'Old thing')

      expect(build_data[:habits].pluck(:name)).not_to include('Old thing')
    end

    # The whole app is time-zone driven; a completion logged late in the user's
    # evening must not land on tomorrow's square.
    it "uses the user's day, not the server's" do
      travel_to Time.utc(2026, 8, 27, 5) do # 10pm Aug 26 in Pacific
        expect(build_data[:today]).to eq('2026-08-26')
      end
    end
  end

  describe 'the activity grid' do
    let!(:meds) { create(:habit, user: user, name: 'Take meds') }
    let!(:run) { create(:habit, user: user, name: 'Exercise') }
    let(:today) { Time.current.in_time_zone(user.zone).to_date }

    it 'is a rectangle of whole weeks' do
      weeks = build_data[:activity][:weeks]

      expect(weeks.map(&:size).uniq).to eq([7])
      expect(weeks.size).to be_between(described_class::ACTIVITY_WEEKS, described_class::ACTIVITY_WEEKS + 1)
    end

    it 'blanks the days outside the window so the corners are not ragged' do
      cells = build_data[:activity][:weeks].flatten

      expect(cells.count { |c| !c[:in_range] }).to be_positive
      expect(cells.select { |c| c[:in_range] }.size).to eq(described_class::ACTIVITY_WEEKS * 7)
    end

    it 'records which habits were done on a day' do
      meds.complete!(today)

      cell = build_data[:activity][:weeks].flatten.find { |c| c[:date] == today.iso8601 }

      expect(cell[:done_ids]).to eq([meds.id])
    end

    # Anything done at all must not render as an empty square.
    it 'gives a partial day a non-zero level' do
      meds.complete!(today)

      cell = build_data[:activity][:weeks].flatten.find { |c| c[:date] == today.iso8601 }

      expect(cell[:level]).to be_between(1, described_class::LEVELS)
    end

    it 'gives a fully completed day the top level' do
      meds.complete!(today)
      run.complete!(today)

      cell = build_data[:activity][:weeks].flatten.find { |c| c[:date] == today.iso8601 }

      expect(cell[:level]).to eq(described_class::LEVELS)
    end

    it 'leaves an untouched day at zero' do
      cell = build_data[:activity][:weeks].flatten.find { |c| c[:date] == (today - 3).iso8601 }

      expect(cell[:level]).to eq(0)
      expect(cell[:done_ids]).to be_empty
    end

    it "does not count another user's completions" do
      theirs = create(:habit, user: create(:user), name: 'Theirs')
      theirs.complete!(today)

      cell = build_data[:activity][:weeks].flatten.find { |c| c[:date] == today.iso8601 }

      expect(cell[:done_ids]).to be_empty
    end
  end
end

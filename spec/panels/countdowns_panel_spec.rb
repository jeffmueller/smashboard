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

  it 'flags whether a dismissal is permanent' do
    create(:countdown, :recurring, user: user, name: 'School')
    create(:countdown, user: user, name: 'Concert', target_at: 10.days.from_now)

    entries = panel.presenter.build[:countdowns].index_by { |c| c[:name] }

    expect(entries['School'][:returns_after_dismissal]).to be(true)
    expect(entries['Concert'][:returns_after_dismissal]).to be(false)
  end

  it 'omits a dismissed occurrence' do
    countdown = create(:countdown, user: user, target_at: 4.hours.from_now)
    countdown.dismiss!(countdown.next_occurrence_at)

    expect(panel.presenter.build[:countdowns]).to be_empty
  end
end

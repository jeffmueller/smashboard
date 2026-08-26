# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TodosPanel do
  let(:user) { create(:user) }
  let(:panel) { create(:panel, user: user, kind: 'todos') }

  it 'shows what is due today and counts what is overdue' do
    create(:todo, user: user, title: 'Due today', due_at: user.zone.now.end_of_day - 1.hour)
    create(:todo, user: user, title: 'Overdue', due_at: 2.days.ago)
    create(:todo, user: user, title: 'Deferred', due_at: 1.hour.from_now, defer_until: 5.days.from_now)

    data = panel.presenter.build

    titles = data[:todos].pluck(:title)
    expect(titles).to include('Due today', 'Overdue')
    expect(titles).not_to include('Deferred')
    expect(data[:overdue_count]).to eq(1)
  end

  it 'honours the configured limit' do
    5.times { |i| create(:todo, user: user, title: "Task #{i}", due_at: 1.hour.from_now) }
    panel.update!(settings: { 'limit' => 2 })

    expect(panel.presenter.build[:todos].size).to eq(2)
  end

  it 'labels due times relative to the user day' do
    create(:todo, user: user, due_at: user.zone.now.end_of_day - 1.hour)

    expect(panel.presenter.build[:todos].first[:due_label]).to match(/\A\d{1,2}:\d{2} (AM|PM)\z/)
  end
end

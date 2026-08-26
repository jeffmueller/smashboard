# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dashboards::InstallDefaults do
  it 'gives a new user a full board' do
    user = create(:user)

    expect(user.panels.count).to eq(described_class::LAYOUT.size)
    expect(user.panels.ordered.pluck(:kind)).to eq(described_class::LAYOUT)
  end

  it 'is idempotent' do
    user = create(:user)

    expect { described_class.new(user).call }.not_to change(user.panels, :count)
  end

  # A panel kind that ships after a user signs up has to reach them somehow;
  # the board has no "add a panel" control, only hide and unhide.
  it 'installs a kind the user does not have yet, at the end of the board' do
    user = create(:user)
    user.panels.find_by(kind: 'bookmarks').destroy!

    expect { described_class.new(user).call }.to change(user.panels, :count).by(1)
    expect(user.panels.ordered.last.kind).to eq('bookmarks')
  end

  it 'leaves the existing order alone when it appends one' do
    user = create(:user)
    user.panels.find_by(kind: 'bookmarks').destroy!
    before = user.panels.ordered.pluck(:kind)

    described_class.new(user).call

    expect(user.panels.ordered.pluck(:kind)).to eq(before + ['bookmarks'])
  end

  # Hiding is how the UI removes a panel, and it keeps the row.
  it 'does not resurrect a panel the user has hidden' do
    user = create(:user)
    user.panels.find_by(kind: 'bookmarks').update!(enabled: false)

    expect { described_class.new(user).call }.not_to change(user.panels, :count)
    expect(user.panels.find_by(kind: 'bookmarks')).not_to be_enabled
  end

  it "applies each panel class's preferred size" do
    user = create(:user)

    expect(user.panels.find_by(kind: 'todos').col_span).to eq(TodosPanel.default_col_span)
    expect(user.panels.find_by(kind: 'clock').col_span).to eq(ClockPanel.default_col_span)
  end
end

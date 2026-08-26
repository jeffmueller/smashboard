# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BookmarksPanel do
  let(:user) { create(:user) }
  let(:panel) { user.panels.find_by(kind: 'bookmarks') }

  it 'is a local panel, so it reads straight from the database' do
    expect(described_class.remote?).to be(false)
  end

  it 'serializes the user\'s bookmarks in order' do
    create(:bookmark, user: user, title: 'Second', url: 'https://b.example.com', position: 1)
    create(:bookmark, user: user, title: 'First', url: 'https://a.example.com', position: 0)

    data = described_class.new(panel).build

    expect(data[:bookmarks].pluck(:title)).to eq(%w[First Second])
  end

  it 'carries what the tile needs to render without another query' do
    create(:bookmark, user: user, title: 'GitHub', url: 'https://www.github.com/x', icon: '🐙')

    bookmark = described_class.new(panel).build[:bookmarks].first

    expect(bookmark).to include(title: 'GitHub', host: 'github.com', icon: '🐙', initial: 'G')
  end

  it 'reports a blank icon as nil so the view can fall back to the initial' do
    create(:bookmark, user: user, title: 'Plain', icon: '')

    expect(described_class.new(panel).build[:bookmarks].first[:icon]).to be_nil
  end

  # An auto-titled bookmark's title already is its host; printing both would
  # show the same string twice in a small tile.
  it 'omits the host when it only repeats the title' do
    create(:bookmark, user: user, url: 'https://arstechnica.com', title: nil)

    bookmark = described_class.new(panel).build[:bookmarks].first

    expect(bookmark[:title]).to eq('arstechnica.com')
    expect(bookmark[:host]).to be_nil
  end

  it 'shows nothing for a user with no bookmarks' do
    expect(described_class.new(panel).build[:bookmarks]).to be_empty
  end

  it 'does not leak another user\'s bookmarks' do
    create(:bookmark, user: create(:user), title: 'Theirs')

    expect(described_class.new(panel).build[:bookmarks]).to be_empty
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positioned do
  let(:user) { create(:user) }

  # Every user is created with the default board; these examples care about
  # ordering a known set, so start from an empty one.
  before { user.panels.destroy_all }

  describe '.apply_order' do
    it 'rewrites positions to match the given order' do
      a = create(:panel, user: user, kind: 'countdowns', position: 0)
      b = create(:panel, user: user, kind: 'todos', position: 1)
      c = create(:panel, user: user, kind: 'news', position: 2)

      user.panels.apply_order([c.id, a.id, b.id])

      expect(user.panels.ordered.pluck(:id)).to eq([c.id, a.id, b.id])
    end

    # The relation is the authorization boundary: an id from outside it is
    # dropped rather than moved, however it got into the request.
    it 'ignores records outside the relation it was called on' do
      mine = create(:panel, user: user, kind: 'countdowns', position: 0)
      theirs = create(:panel, user: create(:user), kind: 'countdowns', position: 0)

      user.panels.apply_order([theirs.id, mine.id])

      expect(mine.reload.position).to eq(0)
      expect(theirs.reload.position).to eq(0)
    end

    it 'refuses an order containing nothing in the relation' do
      expect(user.panels.apply_order([999_999])).to be(false)
    end

    it 'orders bookmarks too' do
      a = create(:bookmark, user: user, position: 0)
      b = create(:bookmark, user: user, position: 1)

      user.bookmarks.apply_order([b.id, a.id])

      expect(user.bookmarks.ordered.pluck(:id)).to eq([b.id, a.id])
    end
  end

  describe '.next_position' do
    it 'lands a new record at the end of the list' do
      create(:panel, user: user, kind: 'countdowns', position: 4)

      expect(user.panels.next_position).to eq(5)
    end

    it 'starts at zero when there is nothing to follow' do
      expect(user.panels.next_position).to eq(0)
    end
  end
end

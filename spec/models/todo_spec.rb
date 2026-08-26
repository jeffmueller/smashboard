# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Todo do
  let(:user) { create(:user) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:todo_project).optional }
  it { is_expected.to validate_presence_of(:title) }

  describe '#complete!' do
    it 'marks a one-off complete without creating anything new' do
      todo = create(:todo, user: user)

      expect { todo.complete! }.not_to change(described_class, :count)
      expect(todo.reload).to be_completed
    end

    it 'schedules the next instance of a repeating todo' do
      todo = create(:todo, :repeating, user: user, due_at: Time.current.change(usec: 0))

      expect { todo.complete! }.to change(described_class, :count).by(1)

      spawned = described_class.incomplete.order(:id).last
      expect(spawned.title).to eq(todo.title)
      expect(spawned.due_at).to be > todo.due_at
      expect(spawned.rrule).to eq(todo.rrule)
    end

    it 'carries the defer window forward relative to the new due date' do
      due = Time.current.change(usec: 0)
      todo = create(:todo, :repeating, user: user, due_at: due, defer_until: due - 2.hours)

      todo.complete!
      spawned = described_class.incomplete.order(:id).last

      expect(spawned.due_at - spawned.defer_until).to be_within(1.second).of(2.hours)
    end
  end

  describe '.for_today' do
    it 'includes items due today' do
      todo = create(:todo, user: user, due_at: user.zone.now.end_of_day - 1.hour)

      expect(described_class.for_today(user)).to include(todo)
    end

    it 'includes flagged items with no due date' do
      todo = create(:todo, user: user, flagged: true, due_at: nil)

      expect(described_class.for_today(user)).to include(todo)
    end

    it 'excludes items deferred into the future' do
      todo = create(:todo, user: user, due_at: 1.hour.from_now, defer_until: 3.days.from_now)

      expect(described_class.for_today(user)).not_to include(todo)
    end

    it 'excludes completed items' do
      todo = create(:todo, user: user, due_at: 1.hour.from_now, completed_at: Time.current)

      expect(described_class.for_today(user)).not_to include(todo)
    end

    it 'excludes another user\'s todos' do
      other = create(:todo, user: create(:user), flagged: true)

      expect(described_class.for_today(user)).not_to include(other)
    end
  end
end

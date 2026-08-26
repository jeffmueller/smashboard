# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Habit do
  let(:user) { create(:user) }
  let(:habit) { create(:habit, user: user, name: 'Take meds') }
  let(:today) { Date.new(2026, 8, 26) }

  describe 'validation' do
    it 'refuses a second habit with the same name for one user, whatever the case' do
      habit # the first one

      expect { create(:habit, user: user, name: 'take MEDS') }
        .to raise_error(ActiveRecord::RecordInvalid, /Name/)
    end

    # And the database agrees, so two concurrent requests can't both slip past
    # the validation. Inserting straight past the model is the only way to ask
    # the index that question.
    it 'has a unique index backing that' do
      habit
      row = { user_id: user.id, name: 'take MEDS', position: 1,
              created_at: Time.current, updated_at: Time.current }

      expect do
        described_class.insert!(row) # rubocop:disable Rails/SkipsModelValidations
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'lets two people keep the same habit' do
      habit

      expect { create(:habit, user: create(:user), name: 'Take meds') }.not_to raise_error
    end
  end

  describe 'completing' do
    it 'records a day' do
      habit.complete!(today)

      expect(habit.completed_on?(today)).to be(true)
    end

    # A double tap on a phone should not be an error, and the unique index
    # would otherwise raise on the second insert.
    it 'is idempotent' do
      habit.complete!(today)

      expect { habit.complete!(today) }.not_to change(HabitCompletion, :count)
    end

    it 'toggles off and on again' do
      expect(habit.toggle_completion!(today)).to be(true)
      expect(habit.toggle_completion!(today)).to be(false)
      expect(habit.completed_on?(today)).to be(false)
    end

    it 'refuses the same day twice at the database level' do
      habit.complete!(today)
      duplicate = HabitCompletion.new(habit: habit, completed_on: today)

      expect(duplicate).not_to be_valid
    end
  end

  describe '#streak' do
    def complete(*offsets)
      offsets.each { |n| habit.complete!(today - n) }
    end

    it 'counts consecutive days ending today' do
      complete(0, 1, 2)

      expect(habit.streak(today: today)).to eq(3)
    end

    # The run is still alive until a day is actually missed; counting only from
    # today would read zero every morning until you checked in.
    it 'survives today not being done yet' do
      complete(1, 2, 3)

      expect(habit.streak(today: today)).to eq(3)
    end

    it 'ends at the first gap' do
      complete(0, 1, 3, 4)

      expect(habit.streak(today: today)).to eq(2)
    end

    it 'is zero when the last completion is older than yesterday' do
      complete(2, 3)

      expect(habit.streak(today: today)).to eq(0)
    end

    it 'is zero for a habit never completed' do
      expect(habit.streak(today: today)).to eq(0)
    end

    it 'ignores days in the future' do
      habit.complete!(today + 5)
      complete(0, 1)

      expect(habit.streak(today: today)).to eq(2)
    end
  end

  describe 'archiving' do
    it 'keeps the history so the graph does not lose its past' do
      habit.complete!(today)
      habit.archive!

      expect(habit).to be_archived
      expect(habit.habit_completions.count).to eq(1)
      expect(user.habits.active).not_to include(habit)
    end

    it 'restores' do
      habit.archive!
      habit.unarchive!

      expect(user.habits.active).to include(habit)
    end
  end

  describe '#initial' do
    it 'is the first letter, upcased' do
      expect(build(:habit, name: 'meditate').initial).to eq('M')
    end
  end

  it 'takes its completions with it when deleted' do
    habit.complete!(today)

    expect { habit.destroy! }.to change(HabitCompletion, :count).by(-1)
  end
end

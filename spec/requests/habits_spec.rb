# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Habits' do
  let(:user) { create(:user, time_zone: 'Pacific Time (US & Canada)') }
  # The controller resolves "today" in the user's zone, so the expectations have
  # to as well. Using the server's date instead makes this file fail only
  # between midnight and 07:00 UTC, when the two disagree.
  let(:today) { user.today }

  before { sign_in user }

  describe 'GET /habits' do
    it 'lists active and archived separately' do
      create(:habit, user: user, name: 'Meditate')
      create(:habit, :archived, user: user, name: 'Retired thing')

      get habits_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Meditate', 'Retired thing', 'Archived')
    end
  end

  describe 'POST /habits' do
    it 'adds a habit with an emoji' do
      expect { post habits_path, params: { habit: { name: 'Exercise', icon: '🏃' } } }
        .to change(user.habits, :count).by(1)

      expect(user.habits.last).to have_attributes(name: 'Exercise', icon: '🏃')
    end

    it 'appends to the end' do
      create(:habit, user: user, position: 0)

      post habits_path, params: { habit: { name: 'Second' } }

      expect(user.habits.ordered.last.position).to eq(1)
    end

    it 'reports a duplicate name rather than raising' do
      create(:habit, user: user, name: 'Meditate')

      post habits_path, params: { habit: { name: 'meditate' } },
                        headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('flash', 'Name')
    end
  end

  describe 'POST /habits/:id/toggle' do
    let!(:habit) { create(:habit, user: user, name: 'Take meds') }

    it 'checks off for today' do
      expect { post toggle_habit_path(habit) }.to change(HabitCompletion, :count).by(1)

      expect(habit.reload.completed_on?(today)).to be(true)
    end

    it 'unchecks when tapped again' do
      post toggle_habit_path(habit)

      expect { post toggle_habit_path(habit) }.to change(HabitCompletion, :count).by(-1)
    end

    # The response has to serve both the board and the management page, since it
    # cannot know which one the tap came from.
    it 'redraws the panel, the list and the form in one response' do
      post toggle_habit_path(habit), headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      targets = response.body.scan(/target="([^"]+)"/).flatten
      expect(targets).to include('habits-list', 'new-habit', 'flash')
      expect(targets.grep(/\Apanel_/)).not_to be_empty
    end

    # A habit checked off at 10pm Pacific belongs to that day, not to the UTC
    # tomorrow the server is already in.
    it "records the user's day" do
      travel_to Time.utc(2026, 8, 27, 5) do
        post toggle_habit_path(habit)

        expect(habit.habit_completions.sole.completed_on).to eq(Date.new(2026, 8, 26))
      end
    end

    it "does not touch another user's habit" do
      theirs = create(:habit, user: create(:user))

      post toggle_habit_path(theirs)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'archiving' do
    let!(:habit) { create(:habit, user: user, name: 'Old thing') }

    it 'keeps the history' do
      habit.complete!(today)

      post archive_habit_path(habit)

      expect(habit.reload).to be_archived
      expect(habit.habit_completions.count).to eq(1)
    end

    it 'restores' do
      post archive_habit_path(habit)
      post unarchive_habit_path(habit)

      expect(habit.reload).not_to be_archived
    end
  end

  describe 'DELETE /habits/:id' do
    it 'takes the history with it' do
      habit = create(:habit, user: user)
      habit.complete!(today)

      expect { delete habit_path(habit) }.to change(HabitCompletion, :count).by(-1)
    end
  end

  describe 'POST /habits/reorder' do
    it 'applies the new order' do
      a = create(:habit, user: user, position: 0)
      b = create(:habit, user: user, position: 1)

      post reorder_habits_path, params: { habit_ids: [b.id, a.id] }

      expect(response).to have_http_status(:no_content)
      expect(user.habits.ordered.pluck(:id)).to eq([b.id, a.id])
    end
  end
end

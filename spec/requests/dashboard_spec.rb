# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dashboard' do
  let(:user) { create(:user) }

  it 'redirects an anonymous visitor to sign in' do
    get root_path

    expect(response).to redirect_to(new_user_session_path)
  end

  # Renders every panel kind on the default board, which is the cheapest way to
  # catch a broken partial in any of them.
  it 'renders the whole default board' do
    sign_in user
    create(:countdown, user: user, name: 'Concert', target_at: 3.days.from_now)
    create(:todo, user: user, title: 'Take the bins out', due_at: user.zone.now.end_of_day - 1.hour)

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Concert', 'Take the bins out')
    # Every panel is built now, so the ones without a connection invite you to
    # add one rather than rendering a not-built-yet placeholder.
    expect(response.body).to include('Connect an account')
    expect(response.body).not_to include('Integration not wired up yet')
  end

  it 'shows a connect prompt for a panel whose integration exists but is unconfigured' do
    sign_in user

    get root_path

    expect(response.body).to include('Connect an account')
  end

  describe 'reordering' do
    it 'persists a new panel order' do
      sign_in user
      ids = user.panels.ordered.pluck(:id)
      reordered = ids.rotate(3)

      post reorder_panels_path, params: { panel_ids: reordered }, as: :json

      expect(response).to have_http_status(:no_content)
      expect(user.panels.ordered.pluck(:id)).to eq(reordered)
    end

    it 'refuses ids that belong to another user' do
      sign_in user
      theirs = create(:user).panels.first

      post reorder_panels_path, params: { panel_ids: [theirs.id] }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'dismissing a countdown from the board' do
    it 'skips the occurrence and re-renders the panel' do
      sign_in user
      countdown = create(:countdown, :recurring, user: user)
      occurrence = countdown.next_occurrence_at

      post dismiss_countdown_path(countdown), params: { occurrence_at: occurrence.iso8601 }

      expect(countdown.reload.next_occurrence_at).to be > occurrence
    end
  end

  describe 'completing a todo from the board' do
    it 'completes it and re-renders the panel' do
      sign_in user
      todo = create(:todo, user: user, due_at: 1.hour.from_now)

      post complete_todo_path(todo)

      expect(todo.reload).to be_completed
    end
  end

  describe 'the meetings panel' do
    it 'renders cached events with a join link for the video call' do
      sign_in user
      create(:connection, user: user, provider: 'caldav', label: 'Fastmail')
      panel = user.panels.find_by!(kind: 'calendar')
      panel.update!(
        data_status: 'ok',
        data_fetched_at: Time.current,
        data: {
          events: [{
            uid: 'evt-1', title: 'Design Review',
            starts_at: 1.hour.from_now.iso8601, ends_at: 2.hours.from_now.iso8601,
            all_day: false, location: 'Room 4B', calendar: 'Work', organizer: 'Dana Lee',
            video_url: 'https://meet.google.com/abc-defg-hij', video_provider: 'Google Meet',
            time_label: '11:00\u201312:00 PM', in_progress: false, finished: false
          }],
          finished_count: 0, calendar_count: 1, partial: false
        }
      )

      get root_path

      expect(response.body).to include('Design Review', 'Room 4B', 'Dana Lee')
      expect(response.body).to include('https://meet.google.com/abc-defg-hij')
      expect(response.body).to include('Google Meet')
    end

    it 'warns when only some calendars could be reached' do
      sign_in user
      create(:connection, user: user, provider: 'caldav', label: 'Fastmail')
      user.panels.find_by!(kind: 'calendar').update!(
        data_status: 'ok', data_fetched_at: Time.current,
        data: { events: [], finished_count: 0, calendar_count: 2, partial: true }
      )

      get root_path

      expect(response.body).to include('No meetings today')
    end
  end
end

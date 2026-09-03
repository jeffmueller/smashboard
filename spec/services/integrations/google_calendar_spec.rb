# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::GoogleCalendar do
  let(:connection) do
    create(:connection,
           provider: 'google_calendar',
           label: 'Personal Google',
           settings: {},
           credentials: { 'refresh_token' => 'refresh-abc' })
  end

  let(:client) { described_class.new(connection) }
  let(:from) { Time.utc(2026, 8, 25, 4) }
  let(:to) { Time.utc(2026, 8, 26, 4) }
  let(:timed_event) do
    {
      id: 'evt-1',
      status: 'confirmed',
      summary: 'Design Review',
      start: { dateTime: '2026-08-25T11:00:00-04:00' },
      end: { dateTime: '2026-08-25T12:00:00-04:00' },
      location: 'Room 4B',
      organizer: { displayName: 'Dana Lee', email: 'dana@example.com' },
      conferenceData: {
        entryPoints: [
          { entryPointType: 'more', uri: 'https://meet.google.com/tel/12345' },
          { entryPointType: 'video', uri: 'https://meet.google.com/abc-defg-hij' }
        ]
      }
    }
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('GOOGLE_CLIENT_ID').and_return('client-id')
    allow(ENV).to receive(:[]).with('GOOGLE_CLIENT_SECRET').and_return('client-secret')
  end

  def stub_token(expires_in: 3600)
    stub_request(:post, 'https://oauth2.googleapis.com/token')
      .to_return(status: 200,
                 body: { access_token: 'access-xyz', expires_in: expires_in }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def stub_calendar_list(items)
    stub_request(:get, 'https://www.googleapis.com/calendar/v3/users/me/calendarList')
      .to_return(status: 200, body: { items: items }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def stub_events(calendar_id, items)
    stub_request(:get, %r{/calendars/#{Regexp.escape(CGI.escape(calendar_id))}/events})
      .to_return(status: 200, body: { items: items }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  describe '#events' do
    before do
      stub_token
      stub_calendar_list([{ id: 'primary', summary: 'Personal' }])
    end

    it 'exchanges the refresh token and calls the API with the access token' do
      events_request = stub_request(:get, %r{/calendars/primary/events})
                       .with(headers: { 'Authorization' => 'Bearer access-xyz' })
                       .to_return(status: 200, body: { items: [] }.to_json,
                                  headers: { 'Content-Type' => 'application/json' })

      client.events(from: from, to: to)

      expect(events_request).to have_been_made
    end

    it 'requests a single-events expansion inside the window' do
      request = stub_request(:get, %r{/calendars/primary/events})
                .with(query: hash_including('singleEvents' => 'true',
                                            'timeMin' => from.iso8601,
                                            'timeMax' => to.iso8601))
                .to_return(status: 200, body: { items: [] }.to_json,
                           headers: { 'Content-Type' => 'application/json' })

      client.events(from: from, to: to)

      expect(request).to have_been_made
    end

    it 'prefers the structured video entry point over other conference links' do
      stub_events('primary', [timed_event])

      event = client.events(from: from, to: to).first

      expect(event[:video_url]).to eq('https://meet.google.com/abc-defg-hij')
      expect(event[:video_provider]).to eq('Google Meet')
    end

    it 'falls back to hangoutLink when there is no conferenceData' do
      stub_events('primary', [timed_event.except(:conferenceData)
                                         .merge(hangoutLink: 'https://meet.google.com/xyz-1234-abc')])

      expect(client.events(from: from, to: to).first[:video_url]).to eq('https://meet.google.com/xyz-1234-abc')
    end

    it 'normalises times to UTC and keeps the location' do
      stub_events('primary', [timed_event])

      event = client.events(from: from, to: to).first

      expect(event[:starts_at]).to eq(Time.utc(2026, 8, 25, 15))
      expect(event[:ends_at]).to eq(Time.utc(2026, 8, 25, 16))
      expect(event[:location]).to eq('Room 4B')
      expect(event[:organizer]).to eq('Dana Lee')
      expect(event[:calendar]).to eq('Personal')
    end

    it 'marks all-day events' do
      stub_events('primary', [{ id: 'h1', status: 'confirmed', summary: 'Holiday',
                                start: { date: '2026-08-25' }, end: { date: '2026-08-26' } }])

      event = client.events(from: from, to: to).first

      expect(event[:all_day]).to be(true)
      expect(event[:ends_at] - event[:starts_at]).to eq(1.day)
    end

    # A date-only boundary is floating. Pinned to UTC it would start at 8pm the
    # evening before for this Eastern user, which reads as the wrong day.
    it 'starts an all-day event at midnight in the user zone' do
      stub_events('primary', [{ id: 'h1', status: 'confirmed', summary: 'Holiday',
                                start: { date: '2026-08-25' }, end: { date: '2026-08-26' } }])

      event = client.events(from: from, to: to).first

      expect(event[:starts_at]).to eq(Time.utc(2026, 8, 25, 4))
      expect(event[:ends_at]).to eq(Time.utc(2026, 8, 26, 4))
    end

    it 'drops cancelled events and ones the user declined' do
      stub_events('primary', [
                    { id: 'c1', status: 'cancelled', summary: 'Called Off',
                      start: { dateTime: '2026-08-25T11:00:00Z' } },
                    { id: 'd1', status: 'confirmed', summary: 'Optional',
                      start: { dateTime: '2026-08-25T12:00:00Z' },
                      attendees: [{ email: 'alex@example.com', self: true, responseStatus: 'declined' }] }
                  ])

      expect(client.events(from: from, to: to)).to be_empty
    end
  end

  describe 'calendar selection' do
    before { stub_token }

    it 'uses every selected calendar when none is configured' do
      stub_calendar_list([
                           { id: 'primary', summary: 'Personal' },
                           { id: 'work@group.calendar.google.com', summary: 'Work' },
                           { id: 'hidden@group.calendar.google.com', summary: 'Hidden', selected: false },
                           { id: 'gone@group.calendar.google.com', summary: 'Gone', deleted: true }
                         ])

      expect(client.calendars.pluck(:name)).to eq(%w[Personal Work])
    end

    it 'honours an explicit comma-separated calendar list without calling calendarList' do
      connection.update!(settings: { 'calendar_ids' => 'primary, work@group.calendar.google.com' })

      expect(client.calendars.pluck(:id)).to eq(['primary', 'work@group.calendar.google.com'])
      expect(a_request(:get, %r{/users/me/calendarList})).not_to have_been_made
    end
  end

  describe 'failures' do
    # Only invalid_grant means the grant is actually dead.
    it 'raises AuthenticationError when Google says the grant is dead' do
      stub_request(:post, 'https://oauth2.googleapis.com/token')
        .to_return(status: 400, body: { error: 'invalid_grant' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect { client.events(from: from, to: to) }
        .to raise_error(Integrations::Base::AuthenticationError, /needs granting again/)
    end

    it 'passes through the subtype so a session policy is distinguishable from a revocation' do
      stub_request(:post, 'https://oauth2.googleapis.com/token')
        .to_return(status: 400, body: { error: 'invalid_grant', error_subtype: 'invalid_rapt' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect { client.events(from: from, to: to) }
        .to raise_error(Integrations::Base::AuthenticationError, /invalid_rapt/)
    end

    # Reporting a bad minute at Google as a dead grant would send the user
    # through a re-consent that fixes nothing.
    it 'treats anything else as transient rather than a dead grant' do
      stub_request(:post, 'https://oauth2.googleapis.com/token').to_return(status: 503, body: '{}')

      expect { client.events(from: from, to: to) }
        .to raise_error(Integrations::Base::Unavailable)
    end

    it 'treats a 400 that is not invalid_grant as transient too' do
      stub_request(:post, 'https://oauth2.googleapis.com/token')
        .to_return(status: 400, body: { error: 'temporarily_unavailable' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect { client.events(from: from, to: to) }
        .to raise_error(Integrations::Base::Unavailable)
    end

    it 'raises AuthenticationError when no refresh token is stored' do
      connection.update!(credentials: {})

      expect { client.events(from: from, to: to) }
        .to raise_error(Integrations::Base::AuthenticationError, /no Google refresh token/)
    end

    it 'raises Unavailable when Google is down, rather than leaking a Faraday error' do
      stub_token
      stub_request(:get, %r{/users/me/calendarList}).to_return(status: 503, body: '{}')

      expect { client.events(from: from, to: to) }.to raise_error(Integrations::Base::Unavailable)
    end

    it 'raises AuthenticationError when the API rejects the access token' do
      stub_token
      stub_request(:get, %r{/users/me/calendarList}).to_return(status: 401, body: '{}')

      expect { client.events(from: from, to: to) }.to raise_error(Integrations::Base::AuthenticationError)
    end
  end
end

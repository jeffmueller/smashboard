# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Caldav do
  let(:connection) do
    create(:connection,
           provider: 'caldav',
           label: 'Fastmail',
           settings: { 'url' => 'https://caldav.example.com/dav/' },
           credentials: { 'username' => 'alex@example.com', 'password' => 'app-password' })
  end

  let(:client) { described_class.new(connection) }
  let(:from) { Time.utc(2026, 8, 25, 4) }
  let(:to) { Time.utc(2026, 8, 26, 4) }
  let(:single_event) do
    <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      UID:standup-1
      SUMMARY:Daily Standup
      DTSTART:20260825T133000Z
      DTEND:20260825T134500Z
      LOCATION:https://acme.zoom.us/j/123
      END:VEVENT
      END:VCALENDAR
    ICS
  end

  # Fastmail's documented address answers 401 to an unauthenticated PROPFIND —
  # so it looks correct when you paste it — and 405 once the credentials are
  # accepted, because the collection lives one level down.
  describe 'discovery when the configured URL is not a DAV collection' do
    let(:connection) do
      create(:connection,
             provider: 'caldav',
             label: 'Fastmail',
             settings: { 'url' => 'https://caldav.example.com/dav' },
             credentials: { 'username' => 'alex@example.com', 'password' => 'app-password' })
    end

    it 'falls back to /.well-known/caldav and finds the calendars anyway' do
      stub_request(:propfind, 'https://caldav.example.com/dav').to_return(status: 405)

      stub_request(:propfind, 'https://caldav.example.com/.well-known/caldav')
        .with(headers: { 'Depth' => '0' })
        .to_return(status: 207, body: multistatus(<<~XML))
          <d:response>
            <d:href>/dav/</d:href>
            <d:propstat>
              <d:prop><d:current-user-principal><d:href>/dav/principals/user/alex/</d:href></d:current-user-principal></d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        XML

      stub_request(:propfind, 'https://caldav.example.com/dav/principals/user/alex/')
        .to_return(status: 207, body: multistatus(<<~XML))
          <d:response>
            <d:href>/dav/principals/user/alex/</d:href>
            <d:propstat>
              <d:prop><c:calendar-home-set><d:href>/dav/calendars/user/alex/</d:href></c:calendar-home-set></d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        XML

      stub_request(:propfind, 'https://caldav.example.com/dav/calendars/user/alex/')
        .with(headers: { 'Depth' => '1' })
        .to_return(status: 207, body: multistatus(<<~XML))
          <d:response>
            <d:href>/dav/calendars/user/alex/personal/</d:href>
            <d:propstat>
              <d:prop>
                <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
                <d:displayname>Personal</d:displayname>
              </d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        XML

      expect(client.calendars.pluck(:name)).to eq(['Personal'])
    end

    # Retrying a rejected password against every candidate path would turn one
    # bad credential into three failed sign-ins on the server.
    it 'does not walk the candidate list when the credentials are refused' do
      refused = stub_request(:propfind, 'https://caldav.example.com/dav').to_return(status: 401)
      well_known = stub_request(:propfind, 'https://caldav.example.com/.well-known/caldav')

      expect { client.calendars }.to raise_error(Integrations::Base::AuthenticationError)
      expect(refused).to have_been_requested
      expect(well_known).not_to have_been_requested
    end

    it 'reports the original failure when nothing on the server answers' do
      stub_request(:propfind, %r{\Ahttps://caldav\.example\.com}).to_return(status: 405)

      expect { client.calendars }
        .to raise_error(Integrations::Base::Unavailable, /405/)
    end
  end

  def multistatus(inner)
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">#{inner}</d:multistatus>
    XML
  end

  def stub_discovery
    stub_request(:propfind, 'https://caldav.example.com/dav/')
      .with(headers: { 'Depth' => '0' })
      .to_return(status: 207, body: multistatus(<<~XML))
        <d:response>
          <d:href>/dav/</d:href>
          <d:propstat>
            <d:prop><d:current-user-principal><d:href>/dav/principals/user/alex/</d:href></d:current-user-principal></d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
          </d:propstat>
        </d:response>
      XML

    stub_request(:propfind, 'https://caldav.example.com/dav/principals/user/alex/')
      .with(headers: { 'Depth' => '0' })
      .to_return(status: 207, body: multistatus(<<~XML))
        <d:response>
          <d:href>/dav/principals/user/alex/</d:href>
          <d:propstat>
            <d:prop><c:calendar-home-set><d:href>/dav/calendars/user/alex/</d:href></c:calendar-home-set></d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
          </d:propstat>
        </d:response>
      XML

    stub_request(:propfind, 'https://caldav.example.com/dav/calendars/user/alex/')
      .with(headers: { 'Depth' => '1' })
      .to_return(status: 207, body: multistatus(<<~XML))
        <d:response>
          <d:href>/dav/calendars/user/alex/</d:href>
          <d:propstat>
            <d:prop><d:resourcetype><d:collection/></d:resourcetype><d:displayname>Home</d:displayname></d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
          </d:propstat>
        </d:response>
        <d:response>
          <d:href>/dav/calendars/user/alex/work/</d:href>
          <d:propstat>
            <d:prop>
              <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
              <d:displayname>Work</d:displayname>
              <c:supported-calendar-component-set><c:comp name="VEVENT"/></c:supported-calendar-component-set>
            </d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
          </d:propstat>
        </d:response>
        <d:response>
          <d:href>/dav/calendars/user/alex/tasks/</d:href>
          <d:propstat>
            <d:prop>
              <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
              <d:displayname>Tasks</d:displayname>
              <c:supported-calendar-component-set><c:comp name="VTODO"/></c:supported-calendar-component-set>
            </d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
          </d:propstat>
        </d:response>
      XML
  end

  def calendar_data(ics)
    multistatus(<<~XML)
      <d:response>
        <d:href>/dav/calendars/user/alex/work/event.ics</d:href>
        <d:propstat>
          <d:prop><c:calendar-data>#{ics.gsub('&', '&amp;').gsub('<', '&lt;')}</c:calendar-data></d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
      </d:response>
    XML
  end

  describe 'discovery' do
    it 'walks principal then calendar-home to find calendars' do
      stub_discovery

      expect(client.calendars).to eq([{ url: 'https://caldav.example.com/dav/calendars/user/alex/work/',
                                        name: 'Work' }])
    end

    it 'ignores collections that are not calendars, and calendars that hold no events' do
      stub_discovery

      expect(client.calendars.pluck(:name)).to eq(%w[Work])
    end

    it 'skips discovery entirely when calendar URLs are configured' do
      connection.update!(settings: connection.settings.merge(
        'calendar_urls' => ['https://caldav.example.com/dav/calendars/user/alex/work/']
      ))

      expect(client.calendars.first[:url]).to eq('https://caldav.example.com/dav/calendars/user/alex/work/')
      expect(a_request(:propfind, 'https://caldav.example.com/dav/')).not_to have_been_made
    end
  end

  describe '#events' do
    before { stub_discovery }

    it 'asks the server to expand recurrences within the window' do
      request = stub_request(:report, 'https://caldav.example.com/dav/calendars/user/alex/work/')
                .with(body: %r{<c:expand start="20260825T040000Z" end="20260826T040000Z"/>})
                .to_return(status: 207, body: calendar_data(single_event))

      client.events(from: from, to: to)

      expect(request).to have_been_made
    end

    it 'authenticates with the stored app password' do
      stub_request(:report, %r{/work/})
        .with(basic_auth: ['alex@example.com', 'app-password'])
        .to_return(status: 207, body: calendar_data(single_event))

      expect(client.events(from: from, to: to).size).to eq(1)
    end

    it 'returns parsed events with their video links' do
      stub_request(:report, %r{/work/}).to_return(status: 207, body: calendar_data(single_event))

      event = client.events(from: from, to: to).first

      expect(event[:title]).to eq('Daily Standup')
      expect(event[:calendar]).to eq('Work')
      expect(event[:video_provider]).to eq('Zoom')
    end

    # Not every CalDAV server implements <c:expand>.
    it 'falls back to unexpanded query and expands recurrences locally' do
      recurring = <<~ICS
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        UID:recurring-1
        SUMMARY:Standup
        DTSTART:20260824T133000Z
        DTEND:20260824T134500Z
        RRULE:FREQ=DAILY
        END:VEVENT
        END:VCALENDAR
      ICS

      stub_request(:report, %r{/work/}).with(body: /c:expand/).to_return(status: 403)
      fallback = stub_request(:report, %r{/work/})
                 .with { |req| req.body.exclude?('c:expand') }
                 .to_return(status: 207, body: calendar_data(recurring))

      events = client.events(from: from, to: to)

      expect(fallback).to have_been_made
      expect(events.size).to eq(1)
      expect(events.first[:starts_at]).to eq(Time.utc(2026, 8, 25, 13, 30))
    end

    it 'raises AuthenticationError on a rejected password' do
      stub_request(:report, %r{/work/}).to_return(status: 401)

      expect { client.events(from: from, to: to) }
        .to raise_error(Integrations::Base::AuthenticationError, /rejected/)
    end

    it 'raises Unavailable when the server errors' do
      stub_request(:report, %r{/work/}).to_return(status: 500)
      stub_request(:report, %r{/work/}).with { |req| req.body.exclude?('c:expand') }.to_return(status: 500)

      expect { client.events(from: from, to: to) }.to raise_error(Integrations::Base::Unavailable)
    end
  end

  it 'refuses to run without a configured server URL' do
    connection.update!(settings: {})

    expect { client.events(from: from, to: to) }
      .to raise_error(Integrations::Base::Unavailable, /no CalDAV server URL/)
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CalendarPanel do
  let(:user) { create(:user, time_zone: 'Eastern Time (US & Canada)') }
  let(:panel) { create(:panel, user: user, kind: 'calendar') }
  let!(:fastmail) { create(:connection, user: user, provider: 'caldav', label: 'Fastmail') }

  # 2026-08-25 10:00 EDT
  let(:now) { Time.utc(2026, 8, 25, 14) }

  def event(title, start_hour, duration: 1, **overrides)
    starts_at = Time.utc(2026, 8, 25, start_hour)
    {
      uid: "#{title.parameterize}-#{start_hour}",
      title: title,
      starts_at: starts_at,
      ends_at: starts_at + duration.hours,
      all_day: false,
      location: nil,
      description: nil,
      calendar: 'Work',
      organizer: nil,
      video_url: nil,
      video_provider: nil,
      rrule: nil,
      exdates: []
    }.merge(overrides)
  end

  # What the clients hand back for a VALUE=DATE event: midnight to midnight in
  # the user's own zone, not in UTC.
  def all_day_event(title, date, **overrides)
    starts_at = user.zone.parse(date).utc

    event(title, 0, **overrides).merge(uid: "#{title.parameterize}-#{date}", starts_at: starts_at,
                                       ends_at: starts_at + 1.day, all_day: true)
  end

  def stub_caldav(events)
    allow(Integrations::Caldav).to receive(:new).and_return(instance_double(Integrations::Caldav, events: events))
  end

  before { travel_to(now) }

  it 'declares itself remote and no longer pending' do
    expect(described_class).to be_remote
    expect(described_class).not_to be_pending
  end

  it 'asks each client for the user day, not the server day' do
    client = instance_double(Integrations::Caldav, events: [])
    allow(Integrations::Caldav).to receive(:new).and_return(client)

    panel.presenter.fetch

    # 2026-08-25 in Eastern is 04:00Z to 03:59:59Z the next day.
    expect(client).to have_received(:events)
      .with(from: Time.utc(2026, 8, 25, 4), to: be_within(1.second).of(Time.utc(2026, 8, 26, 3, 59, 59)))
  end

  it 'hides meetings that already finished but counts them' do
    stub_caldav([event('Morning Sync', 12), event('Design Review', 15)])

    payload = panel.presenter.fetch

    expect(payload[:events].pluck(:title)).to eq(['Design Review'])
    expect(payload[:finished_count]).to eq(1)
  end

  it 'shows finished meetings when asked to' do
    panel.update!(settings: { 'show_finished' => true })
    stub_caldav([event('Morning Sync', 12), event('Design Review', 15)])

    payload = panel.presenter.fetch

    expect(payload[:events].pluck(:title)).to eq(['Morning Sync', 'Design Review'])
    expect(payload[:events].first[:finished]).to be(true)
  end

  it 'flags a meeting that is happening right now' do
    stub_caldav([event('Standup', 13, duration: 2)])

    expect(panel.presenter.fetch[:events].first[:in_progress]).to be(true)
  end

  it 'sorts all-day events first, then by start time' do
    stub_caldav([
                  event('Late', 20),
                  all_day_event('Holiday', '2026-08-25'),
                  event('Early', 15)
                ])

    expect(panel.presenter.fetch[:events].pluck(:title)).to eq(%w[Holiday Early Late])
  end

  it 'labels a timed event with its span and an all-day event plainly' do
    stub_caldav([event('Design Review', 15), all_day_event('Holiday', '2026-08-25')])

    labels = panel.presenter.fetch[:events].to_h { |e| [e[:title], e[:time_label]] }

    expect(labels['Design Review']).to eq('11:00–12:00 PM')
    expect(labels['Holiday']).to eq('All day')
  end

  # A CalDAV server matches a floating all-day date against the requested range
  # in UTC (RFC 4791), so an Eastern user's Tuesday query also comes back with
  # Wednesday's all-day events. They are never "finished", so nothing else drops
  # them.
  it 'drops an all-day event belonging to another day' do
    stub_caldav([all_day_event('Yesterday Holiday', '2026-08-24'),
                 all_day_event('Today Holiday', '2026-08-25'),
                 all_day_event('Tomorrow Holiday', '2026-08-26')])

    expect(panel.presenter.fetch[:events].pluck(:title)).to eq(['Today Holiday'])
  end

  it 'keeps a multi-day event that runs through today' do
    conference = all_day_event('Conference', '2026-08-24')
                 .merge(ends_at: user.zone.parse('2026-08-27').utc)

    stub_caldav([conference])

    expect(panel.presenter.fetch[:events].pluck(:title)).to eq(['Conference'])
  end

  # An event with no DTEND is a point in time rather than an interval, and one
  # sitting exactly on midnight fails an overlap test.
  it 'keeps an instantaneous event at the very start of the day' do
    panel.update!(settings: { 'show_finished' => true })
    stub_caldav([event('Rent Due', 4, duration: 0)])

    expect(panel.presenter.fetch[:events].pluck(:title)).to eq(['Rent Due'])
  end

  it 'passes the video link through to the payload' do
    stub_caldav([event('Design Review', 15, video_url: 'https://meet.google.com/abc-defg-hij',
                                            video_provider: 'Google Meet')])

    entry = panel.presenter.fetch[:events].first

    expect(entry[:video_url]).to eq('https://meet.google.com/abc-defg-hij')
    expect(entry[:video_provider]).to eq('Google Meet')
  end

  context 'with two connected accounts' do
    let!(:google) { create(:connection, user: user, provider: 'google_calendar', label: 'Google') }

    it 'merges events from both' do
      allow(Integrations::Caldav).to receive(:new)
        .and_return(instance_double(Integrations::Caldav, events: [event('From Fastmail', 15)]))
      allow(Integrations::GoogleCalendar).to receive(:new)
        .and_return(instance_double(Integrations::GoogleCalendar, events: [event('From Google', 16)]))

      expect(panel.presenter.fetch[:events].pluck(:title)).to eq(['From Fastmail', 'From Google'])
    end

    # A shared work calendar subscribed in both accounts shouldn't show twice.
    it 'deduplicates the same meeting arriving from both accounts' do
      allow(Integrations::Caldav).to receive(:new)
        .and_return(instance_double(Integrations::Caldav, events: [event('All Hands', 16)]))
      allow(Integrations::GoogleCalendar).to receive(:new)
        .and_return(instance_double(Integrations::GoogleCalendar, events: [event('All Hands', 16)]))

      expect(panel.presenter.fetch[:events].size).to eq(1)
    end

    it 'keeps working when one account fails, and says the list is partial' do
      allow(Integrations::Caldav).to receive(:new)
        .and_raise(Integrations::Base::Unavailable, 'server down')
      allow(Integrations::GoogleCalendar).to receive(:new)
        .and_return(instance_double(Integrations::GoogleCalendar, events: [event('Design Review', 15)]))

      payload = panel.presenter.fetch

      expect(payload[:events].pluck(:title)).to eq(['Design Review'])
      expect(payload[:partial]).to be(true)
      expect(fastmail.reload.status).to eq('error')
      expect(google.reload.status).to eq('ok')
    end
  end

  describe 'what counts as worth interrupting someone for' do
    let!(:device) { create(:push_subscription, user: user) }

    before { capture_pushes }

    it 'warns about a dead grant, which the user can fix' do
      allow(Integrations::Caldav).to receive(:new)
        .and_raise(Integrations::Base::AuthenticationError, 'credentials rejected')

      panel.presenter.refresh!

      expect(sent_pushes.size).to eq(1)
    end

    # A timeout will very likely fix itself before anyone reads about it.
    it 'stays quiet about a transient failure' do
      allow(Integrations::Caldav).to receive(:new)
        .and_raise(Integrations::Base::Unavailable, 'server had a moment')

      panel.presenter.refresh!

      expect(sent_pushes).to be_empty
      expect(fastmail.reload.status).to eq('error')
    end
  end

  it 'parks the panel in an error state when every account fails' do
    allow(Integrations::Caldav).to receive(:new).and_raise(Integrations::Base::Unavailable, 'server down')

    expect { panel.presenter.refresh! }.not_to raise_error

    expect(panel.reload.data_status).to eq('error')
    expect(panel.last_error).to include('server down')
  end

  it 'reports itself unconfigured with no calendar connection' do
    fastmail.destroy

    expect(panel.reload.presenter).not_to be_configured
  end
end

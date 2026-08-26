# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WeatherPanel do
  let(:user) { create(:user) }
  let!(:home) { create(:connection, user: user, provider: 'nws', label: 'Home') }
  let(:panel) { user.panels.find_by!(kind: 'weather') }

  def alert(event:, severity:, id: "urn:#{event.parameterize}")
    { id: id, event: event, severity: severity, headline: "#{event} issued", area: 'Somewhere',
      description: 'Details', sender: 'NWS', starts_at: nil, ends_at: nil }
  end

  def stub_nws(alerts: [], conditions: nil, radar_url: 'https://radar.weather.gov/ridge/standard/KLWX_loop.gif')
    allow(Integrations::Nws).to receive(:new).and_return(
      instance_double(Integrations::Nws,
                      location: Weather::Location::Result.new(latitude: 1, longitude: 2, label: 'Home'),
                      alerts: alerts, conditions: conditions, radar_url: radar_url)
    )
  end

  it 'is no longer pending and reads both NWS and a personal station' do
    expect(described_class).not_to be_pending
    expect(described_class.required_providers).to contain_exactly('nws', 'weather_station')
  end

  it 'reports conditions, alerts and a radar loop' do
    stub_nws(alerts: [alert(event: 'Red Flag Warning', severity: 'severe')],
             conditions: { temperature_f: 76, humidity: 54, station: 'KNYC' })

    payload = panel.presenter.fetch

    expect(payload[:location]).to eq('Home')
    expect(payload[:conditions]).to include(temperature_f: 76)
    expect(payload[:alerts].pluck(:event)).to eq(['Red Flag Warning'])
    expect(payload[:radar_url]).to end_with('_loop.gif')
  end

  it 'puts the loudest alert first' do
    stub_nws(alerts: [alert(event: 'Air Quality Alert', severity: 'unknown'),
                      alert(event: 'Extreme Heat Warning', severity: 'extreme'),
                      alert(event: 'Wind Advisory', severity: 'moderate')])

    expect(panel.presenter.fetch[:alerts].pluck(:event))
      .to eq(['Extreme Heat Warning', 'Wind Advisory', 'Air Quality Alert'])
  end

  it 'leaves the radar out when it is switched off' do
    stub_nws
    panel.update!(settings: { 'show_radar' => false })

    expect(panel.presenter.fetch[:radar_url]).to be_nil
  end

  it 'parks the panel in an error state when NWS cannot be reached' do
    allow(Integrations::Nws).to receive(:new).and_raise(Integrations::Base::Unavailable, 'NWS down')

    expect { panel.presenter.refresh! }.not_to raise_error
    expect(panel.reload.data_status).to eq('error')
  end

  describe 'alert notifications' do
    let!(:device) { create(:push_subscription, user: user) }

    before { capture_pushes }

    it 'announces a severe alert' do
      stub_nws(alerts: [alert(event: 'Red Flag Warning', severity: 'severe')])

      panel.presenter.refresh!

      message = JSON.parse(sent_pushes.first[:message])
      expect(message).to include('title' => 'Red Flag Warning', 'body' => 'Red Flag Warning issued')
      # A severe-weather warning should stay up until acknowledged.
      expect(message['require_interaction']).to be(true)
    end

    # The shipped default threshold is "severe".
    it 'ignores anything below the severity threshold' do
      stub_nws(alerts: [alert(event: 'Air Quality Alert', severity: 'unknown'),
                        alert(event: 'Wind Advisory', severity: 'moderate')])

      panel.presenter.refresh!

      expect(sent_pushes).to be_empty
    end

    it 'announces an extreme alert, which outranks the threshold' do
      stub_nws(alerts: [alert(event: 'Tornado Warning', severity: 'extreme')])

      panel.presenter.refresh!

      expect(sent_pushes.size).to eq(1)
    end

    it 'honours a lowered threshold' do
      create(:notification_preference, user: user, kind: 'weather_alert',
                                       settings: { 'minimum_severity' => 'minor' })
      stub_nws(alerts: [alert(event: 'Wind Advisory', severity: 'moderate')])

      panel.presenter.refresh!

      expect(sent_pushes.size).to eq(1)
    end

    it 'announces a standing alert only once' do
      stub_nws(alerts: [alert(event: 'Red Flag Warning', severity: 'severe')])

      3.times { panel.presenter.refresh! }

      expect(sent_pushes.size).to eq(1)
    end

    it 'announces a newly issued alert' do
      stub_nws(alerts: [alert(event: 'Red Flag Warning', severity: 'severe')])
      panel.presenter.refresh!

      stub_nws(alerts: [alert(event: 'Red Flag Warning', severity: 'severe'),
                        alert(event: 'Extreme Heat Warning', severity: 'extreme')])
      panel.presenter.refresh!

      expect(sent_pushes.size).to eq(2)
    end

    it 'stays quiet when weather alerts are switched off' do
      create(:notification_preference, user: user, kind: 'weather_alert', enabled: false)
      stub_nws(alerts: [alert(event: 'Tornado Warning', severity: 'extreme')])

      panel.presenter.refresh!

      expect(sent_pushes).to be_empty
    end
  end

  describe 'with a personal weather station as well' do
    let!(:station) do
      create(:connection, user: user, provider: 'weather_station', label: 'Back garden',
                          settings: { 'vendor' => 'tempest' })
    end

    def stub_station(conditions)
      allow(Integrations::Tempest).to receive(:new)
        .and_return(instance_double(Integrations::Tempest, conditions: conditions))
    end

    # A station in your own garden beats the airport twenty miles away.
    it 'prefers the station reading over the NWS one' do
      stub_nws(conditions: { source: 'nws', temperature_f: 76, station: 'KNYC' })
      stub_station({ source: 'station', temperature_f: 81, station: 'Back garden', uv: 6 })

      conditions = panel.presenter.fetch[:conditions]

      expect(conditions[:temperature_f]).to eq(81)
      expect(conditions[:station]).to eq('Back garden')
      expect(conditions[:uv]).to eq(6)
    end

    it 'still takes alerts and radar from NWS' do
      stub_nws(alerts: [alert(event: 'Red Flag Warning', severity: 'severe')],
               conditions: { source: 'nws', temperature_f: 76 })
      stub_station({ source: 'station', temperature_f: 81 })

      payload = panel.presenter.fetch

      expect(payload[:alerts].pluck(:event)).to eq(['Red Flag Warning'])
      expect(payload[:radar_url]).to end_with('_loop.gif')
    end

    it 'falls back to NWS conditions when the station is unreachable' do
      stub_nws(alerts: [alert(event: 'Red Flag Warning', severity: 'severe')],
               conditions: { source: 'nws', temperature_f: 76 })
      allow(Integrations::Tempest).to receive(:new)
        .and_raise(Integrations::Base::Unavailable, 'station offline')

      payload = panel.presenter.fetch

      expect(payload[:conditions][:temperature_f]).to eq(76)
      expect(payload[:alerts].size).to eq(1)
      expect(payload[:partial]).to be(true)
      expect(station.reload.status).to eq('error')
    end

    it 'says so plainly for a brand it has no client for' do
      stub_nws
      station.update!(settings: { 'vendor' => 'acme-weather-9000' })

      panel.presenter.refresh!

      expect(station.reload.last_error).to include('unsupported weather station: acme-weather-9000')
    end
  end
end

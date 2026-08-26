# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Nws do
  let(:user) { create(:user, postal_code: nil) }
  let(:connection) do
    create(:connection, user: user, provider: 'nws', label: 'Home',
                        settings: { 'latitude' => '38.8894', 'longitude' => '-77.0352', 'label' => 'Home' })
  end

  let(:client) { described_class.new(connection) }
  let(:point) { '38.8894,-77.0352' }

  def geo_json(body)
    { status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/geo+json' } }
  end

  def stub_point(radar_station: 'KLWX')
    stub_request(:get, "https://api.weather.gov/points/#{point}")
      .to_return(geo_json({ properties: {
                            gridId: 'LWX', radarStation: radar_station,
                            observationStations: 'https://api.weather.gov/gridpoints/LWX/97,71/stations'
                          } }))
  end

  def stub_stations(*identifiers)
    stub_request(:get, 'https://api.weather.gov/gridpoints/LWX/97,71/stations')
      .to_return(geo_json({ features: identifiers.map { |id| { properties: { stationIdentifier: id } } } }))
  end

  # Shapes taken from live api.weather.gov responses.
  def measurement(value, unit)
    { 'value' => value, 'unitCode' => unit }
  end

  def stub_observation(station, properties)
    stub_request(:get, "https://api.weather.gov/stations/#{station}/observations/latest")
      .to_return(geo_json({ properties: properties }))
  end

  def stub_alerts(*alerts)
    stub_request(:get, 'https://api.weather.gov/alerts/active')
      .with(query: { point: point })
      .to_return(geo_json({ features: alerts.map { |a| { properties: a } } }))
  end

  def alert(event:, severity:, id: SecureRandom.uuid, onset: '2026-08-25T10:42:00-07:00')
    { id: id, event: event, severity: severity, urgency: 'Expected', certainty: 'Likely',
      headline: "#{event} issued August 25", areaDesc: 'Santa Susana Mountains',
      description: "  * WHAT...Something\n\n  * WHERE...There  ", instruction: 'Take care',
      senderName: 'NWS Los Angeles/Oxnard CA', onset: onset, ends: '2026-08-28T20:00:00-07:00' }
  end

  describe '#alerts' do
    it 'identifies the app to NWS, which throttles anonymous traffic' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('NWS_USER_AGENT', anything).and_return('smashboard (me@example.com)')
      request = stub_alerts

      client.alerts

      expect(request.with(headers: { 'User-Agent' => 'smashboard (me@example.com)' })).to have_been_made
    end

    it 'normalises an alert' do
      stub_alerts(alert(event: 'Red Flag Warning', severity: 'Severe', id: 'urn:oid:1'))

      result = client.alerts.first

      expect(result).to include(
        id: 'urn:oid:1', event: 'Red Flag Warning', severity: 'severe',
        area: 'Santa Susana Mountains', sender: 'NWS Los Angeles/Oxnard CA'
      )
      expect(result[:starts_at]).to eq('2026-08-25T10:42:00-07:00')
    end

    it 'squishes the wrapped CAP description into something renderable' do
      stub_alerts(alert(event: 'Red Flag Warning', severity: 'Severe'))

      expect(client.alerts.first[:description]).to eq('* WHAT...Something * WHERE...There')
    end

    it 'puts the loudest alert first' do
      stub_alerts(alert(event: 'Air Quality Alert', severity: 'Unknown'),
                  alert(event: 'Extreme Heat Warning', severity: 'Extreme'),
                  alert(event: 'Red Flag Warning', severity: 'Severe'))

      expect(client.alerts.pluck(:event))
        .to eq(['Extreme Heat Warning', 'Red Flag Warning', 'Air Quality Alert'])
    end

    it 'returns nothing when the area is quiet' do
      stub_alerts

      expect(client.alerts).to be_empty
    end
  end

  describe '#conditions' do
    before do
      stub_point
      stub_stations('KDCA', 'KCGS')
    end

    # NWS reports SI regardless of locale.
    it 'converts SI units to the ones the panel shows' do
      stub_observation('KDCA', {
                         timestamp: '2026-08-25T22:20:00+00:00',
                         textDescription: 'Cloudy',
                         temperature: measurement(27, 'wmoUnit:degC'),
                         dewpoint: measurement(14, 'wmoUnit:degC'),
                         relativeHumidity: measurement(44.83, 'wmoUnit:percent'),
                         windSpeed: measurement(14.832, 'wmoUnit:km_h-1'),
                         windDirection: measurement(330, 'wmoUnit:degree_(angle)'),
                         barometricPressure: measurement(101_693.25, 'wmoUnit:Pa')
                       })

      conditions = client.conditions

      expect(conditions).to include(
        station: 'KDCA', summary: 'Cloudy',
        temperature_f: 81, dewpoint_f: 57, humidity: 45,
        wind_mph: 9, wind_direction: 'NNW', pressure_in: 30.03
      )
    end

    it 'handles a station reporting metres per second' do
      stub_observation('KDCA', { windSpeed: measurement(10, 'wmoUnit:m_s-1') })

      expect(client.conditions[:wind_mph]).to eq(22)
    end

    it 'leaves values a station does not report as nil' do
      stub_observation('KDCA', { temperature: measurement(20, 'wmoUnit:degC'),
                                 windSpeed: measurement(nil, 'wmoUnit:km_h-1'),
                                 barometricPressure: nil })

      conditions = client.conditions

      expect(conditions[:temperature_f]).to eq(68)
      expect(conditions[:wind_mph]).to be_nil
      expect(conditions[:pressure_in]).to be_nil
    end

    it 'uses the nearest station' do
      stub_observation('KDCA', { textDescription: 'Clear' })

      expect(client.conditions[:station]).to eq('KDCA')
    end

    it 'returns nothing when the grid point lists no stations' do
      stub_stations

      expect(client.conditions).to be_nil
    end

    # Alerts matter more than conditions; a dead station shouldn't cost both.
    it 'gives up quietly when the station will not answer' do
      stub_request(:get, %r{/stations/KDCA/observations/latest}).to_return(status: 503, body: '{}')

      expect(client.conditions).to be_nil
    end
  end

  describe '#radar_url' do
    it 'builds a loop URL for the point radar station' do
      stub_point(radar_station: 'KVTX')

      expect(client.radar_url).to eq('https://radar.weather.gov/ridge/standard/KVTX_loop.gif')
    end

    it 'is nil where there is no radar station' do
      stub_point(radar_station: nil)

      expect(client.radar_url).to be_nil
    end
  end

  describe 'failures' do
    it 'reports an NWS outage as unavailable' do
      stub_request(:get, %r{alerts/active}).to_return(status: 503, body: '{}')

      expect { client.alerts }.to raise_error(Integrations::Base::Unavailable)
    end

    it 'refuses to guess a location' do
      connection.update!(settings: {})

      expect { client.alerts }.to raise_error(Integrations::Base::Unavailable, /no location set/)
    end
  end
end

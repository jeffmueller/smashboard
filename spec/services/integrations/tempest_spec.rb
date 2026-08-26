# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Tempest do
  let(:connection) do
    create(:connection, provider: 'weather_station', label: 'Back garden',
                        settings: { 'vendor' => 'tempest', 'station_id' => '12345' },
                        credentials: { 'token' => 'pat-secret' })
  end

  let(:client) { described_class.new(connection) }
  # Shape per the documented better_forecast response.
  let(:current_conditions) do
    {
      time: 1_787_700_000,
      conditions: 'Partly Cloudy',
      air_temperature: 76.3,
      feels_like: 78.1,
      dew_point: 57.4,
      relative_humidity: 54.2,
      wind_avg: 8.6,
      wind_gust: 14.2,
      wind_direction: 330,
      wind_direction_cardinal: 'NNW',
      sea_level_pressure: 30.031,
      pressure_trend: 'falling',
      uv: 6.4,
      precip_accum_local_day: 0.12,
      lightning_strike_count_last_3hr: 3
    }
  end

  def json(body, status: 200)
    { status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def stub_forecast(conditions = current_conditions, station_name: 'Back garden')
    stub_request(:get, %r{swd\.weatherflow\.com/swd/rest/better_forecast})
      .to_return(json({ status: { status_code: 0, status_message: 'SUCCESS' },
                        station_name: station_name,
                        current_conditions: conditions }))
  end

  describe '#conditions' do
    it 'asks for imperial units so nothing has to be converted here' do
      request = stub_forecast

      client.conditions

      expect(request.with(query: hash_including('units_temp' => 'f', 'units_wind' => 'mph',
                                                'units_pressure' => 'inhg', 'station_id' => '12345')))
        .to have_been_made
    end

    it 'authenticates with the personal access token' do
      request = stub_forecast

      client.conditions

      expect(request.with(query: hash_including('token' => 'pat-secret'))).to have_been_made
    end

    it 'normalises into the same shape the NWS client produces' do
      stub_forecast

      expect(client.conditions).to include(
        source: 'station', station: 'Back garden', summary: 'Partly Cloudy',
        temperature_f: 76, feels_like_f: 78, dewpoint_f: 57, humidity: 54,
        wind_mph: 9, wind_gust_mph: 14, wind_direction: 'NNW', pressure_in: 30.03
      )
    end

    it 'reports the readings only a station in your own garden has' do
      stub_forecast

      expect(client.conditions).to include(uv: 6, rain_today_in: 0.12,
                                           lightning_strikes_3h: 3, pressure_trend: 'falling')
    end

    it 'converts the epoch timestamp' do
      stub_forecast

      expect(client.conditions[:observed_at]).to eq(Time.at(1_787_700_000).utc.iso8601)
    end

    it 'derives a cardinal direction when the API omits one' do
      stub_forecast(current_conditions.except(:wind_direction_cardinal))

      expect(client.conditions[:wind_direction]).to eq('NNW')
    end

    it 'drops readings the station does not report rather than showing blanks' do
      stub_forecast({ time: 1_787_700_000, air_temperature: 70.0 })

      conditions = client.conditions

      expect(conditions[:temperature_f]).to eq(70)
      expect(conditions).not_to have_key(:uv)
      expect(conditions).not_to have_key(:wind_mph)
    end

    it 'returns nothing when the station reports no current conditions' do
      stub_request(:get, /better_forecast/)
        .to_return(json({ status: { status_code: 0 }, current_conditions: nil }))

      expect(client.conditions).to be_nil
    end
  end

  describe 'station discovery' do
    it 'uses the first station when none is configured' do
      connection.update!(settings: { 'vendor' => 'tempest' })
      stub_request(:get, %r{swd\.weatherflow\.com/swd/rest/stations})
        .to_return(json({ status: { status_code: 0 },
                          stations: [{ station_id: 999, name: 'Back garden' },
                                     { station_id: 1000, name: 'Roof' }] }))
      request = stub_forecast

      client.conditions

      expect(request.with(query: hash_including('station_id' => '999'))).to have_been_made
    end

    it 'says so when the account has no stations' do
      connection.update!(settings: { 'vendor' => 'tempest' })
      stub_request(:get, %r{/stations}).to_return(json({ status: { status_code: 0 }, stations: [] }))

      expect { client.conditions }.to raise_error(Integrations::Base::Unavailable, /no stations/)
    end
  end

  describe 'failures' do
    it 'raises AuthenticationError with no token stored' do
      connection.update!(credentials: {})

      expect { client.conditions }
        .to raise_error(Integrations::Base::AuthenticationError, /no Tempest personal access token/)
    end

    it 'raises AuthenticationError on a rejected token' do
      stub_request(:get, /better_forecast/)
        .to_return(json({ status: { status_code: 401, status_message: 'UNAUTHORIZED' } }, status: 401))

      expect { client.conditions }
        .to raise_error(Integrations::Base::AuthenticationError, /UNAUTHORIZED/)
    end

    # Tempest answers some failures with a 200 and a non-zero envelope code.
    it 'catches a failure hidden behind a 200' do
      stub_request(:get, /better_forecast/)
        .to_return(json({ status: { status_code: 5, status_message: 'INVALID STATION ID' } }))

      expect { client.conditions }
        .to raise_error(Integrations::Base::Unavailable, /INVALID STATION ID/)
    end

    it 'reports an outage as unavailable' do
      stub_request(:get, /better_forecast/).to_return(status: 503, body: '{}')

      expect { client.conditions }.to raise_error(Integrations::Base::Unavailable)
    end
  end
end

# frozen_string_literal: true

module Integrations
  # A WeatherFlow Tempest station, read through the `better_forecast` endpoint.
  #
  # That endpoint is used in preference to `observations/station/{id}` because
  # it accepts explicit unit parameters — so the reply comes back in the units
  # this app displays rather than whatever the station happens to be configured
  # for — and it carries a human conditions string and a cardinal wind direction
  # that the raw observation feed doesn't.
  class Tempest < Base
    BASE_URL = 'https://swd.weatherflow.com/swd/rest/'
    STATION_TTL = 7.days

    # Asking for these means no unit conversion has to happen here at all.
    IMPERIAL = {
      units_temp: 'f',
      units_wind: 'mph',
      units_pressure: 'inhg',
      units_precip: 'in',
      units_distance: 'mi'
    }.freeze

    COMPASS = %w[N NNE NE ENE E ESE SE SSE S SSW SW WSW W WNW NW NNW].freeze

    def conditions
      body = request { get('better_forecast', station_id: station_id, **IMPERIAL) }
      current = body['current_conditions']
      return nil if current.blank?

      normalize(current, body)
    end

    # Exposed so a connection with no station_id can be told what was found.
    def stations
      body = request { get('stations') }

      Array(body['stations']).map do |station|
        { id: station['station_id'], name: station['name'].presence || station['public_name'] }
      end
    end

    private

    def normalize(current, body)
      {
        source: 'station',
        station: body['station_name'].presence || station_id.to_s,
        observed_at: to_iso8601(current['time']),
        summary: current['conditions'].presence,
        temperature_f: round(current['air_temperature']),
        feels_like_f: round(current['feels_like']),
        dewpoint_f: round(current['dew_point']),
        humidity: round(current['relative_humidity']),
        wind_mph: round(current['wind_avg']),
        wind_gust_mph: round(current['wind_gust']),
        wind_direction: current['wind_direction_cardinal'].presence || to_compass(current['wind_direction']),
        pressure_in: current['sea_level_pressure']&.round(2),
        pressure_trend: current['pressure_trend'].presence,
        # Things only a station in your own garden can tell you.
        uv: round(current['uv']),
        rain_today_in: current['precip_accum_local_day']&.round(2),
        lightning_strikes_3h: current['lightning_strike_count_last_3hr']
      }.compact
    end

    def station_id
      @station_id ||= setting('station_id').presence ||
                      Rails.cache.fetch(cache_key('station'), expires_in: STATION_TTL) { discover_station_id }
    end

    def discover_station_id
      first = stations.first
      raise Unavailable, 'this Tempest account has no stations' if first.blank?

      first[:id]
    end

    def get(path, params = {})
      response = http(BASE_URL).get(path, params.merge(token: token))
      # Tempest answers some failures with a 200 and a non-zero status code, so
      # the envelope has to be checked as well as the HTTP status.
      guard_envelope(response)
      response
    end

    def guard_envelope(response)
      code = response.body.is_a?(Hash) ? response.body.dig('status', 'status_code') : nil
      return if code.nil? || code.to_i.zero?

      message = response.body.dig('status', 'status_message').presence || "status #{code}"
      raise AuthenticationError, "Tempest rejected the request: #{message}" if response.status == 401

      raise Unavailable, "Tempest returned #{message}"
    end

    def round(value)
      value&.round
    end

    def to_iso8601(epoch)
      return nil if epoch.blank?

      Time.at(epoch.to_i).utc.iso8601
    end

    def to_compass(degrees)
      return nil if degrees.nil?

      COMPASS[((degrees.to_f / 22.5) + 0.5).floor % 16]
    end

    def token
      credentials['token'].presence ||
        raise(AuthenticationError, 'no Tempest personal access token stored for this connection')
    end

    def cache_key(suffix)
      "tempest/#{connection.id}/#{suffix}"
    end
  end
end

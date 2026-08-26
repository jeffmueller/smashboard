# frozen_string_literal: true

module Integrations
  # The National Weather Service API: active alerts, current conditions from the
  # nearest reporting station, and a radar loop.
  #
  # No API key — NWS asks only for a User-Agent that identifies the app and how
  # to reach whoever runs it, which is what NWS_USER_AGENT is for.
  #
  # Everything comes back in SI units (degC, km/h, Pa) regardless of locale, so
  # conversion happens here rather than in the view.
  class Nws < Base
    BASE_URL = 'https://api.weather.gov/'
    RADAR_URL = 'https://radar.weather.gov/ridge/standard/%<station>s_loop.gif'

    # A grid point and its radar station never change; the station list rarely
    # does. Both are cached hard so a refresh is one request, not four.
    POINT_TTL = 30.days
    STATION_TTL = 7.days

    # Least to most urgent, matching the NWS CAP severity vocabulary.
    SEVERITIES = %w[unknown minor moderate severe extreme].freeze

    COMPASS = %w[N NNE NE ENE E ESE SE SSE S SSW SW WSW W WNW NW NNW].freeze

    def location
      @location ||= Weather::Location.for(connection)
    end

    def alerts
      body = request { get('alerts/active', point: point_parameter) }

      Array(body['features'])
        .map { |feature| normalize_alert(feature['properties'] || {}) }
        .sort_by { |alert| [-severity_rank(alert[:severity]), alert[:starts_at].to_s] }
    end

    def conditions
      station = observation_station
      return nil if station.blank?

      body = request { get("stations/#{station}/observations/latest") }
      normalize_observation(body['properties'] || {}, station)
    rescue Unavailable
      # A station that has gone quiet shouldn't cost us the alerts as well.
      nil
    end

    def radar_url
      station = point_properties['radarStation'].presence
      station && format(RADAR_URL, station: station)
    end

    def self.severity_rank(severity)
      SEVERITIES.index(severity.to_s.downcase) || 0
    end

    private

    def severity_rank(severity)
      self.class.severity_rank(severity)
    end

    def normalize_alert(properties)
      {
        id: properties['id'],
        event: properties['event'],
        severity: properties['severity'].to_s.downcase,
        urgency: properties['urgency'].to_s.downcase,
        certainty: properties['certainty'].to_s.downcase,
        headline: properties['headline'],
        area: properties['areaDesc'],
        description: properties['description'].to_s.squish.presence,
        instruction: properties['instruction'].to_s.squish.presence,
        sender: properties['senderName'],
        starts_at: properties['onset'].presence || properties['effective'].presence,
        ends_at: properties['ends'].presence || properties['expires'].presence
      }
    end

    def normalize_observation(properties, station)
      {
        station: station,
        observed_at: properties['timestamp'],
        summary: properties['textDescription'].presence,
        temperature_f: to_fahrenheit(properties['temperature']),
        dewpoint_f: to_fahrenheit(properties['dewpoint']),
        feels_like_f: to_fahrenheit(properties['heatIndex']) || to_fahrenheit(properties['windChill']),
        humidity: percentage(properties['relativeHumidity']),
        wind_mph: to_mph(properties['windSpeed']),
        wind_gust_mph: to_mph(properties['windGust']),
        wind_direction: to_compass(properties.dig('windDirection', 'value')),
        pressure_in: to_inches_of_mercury(properties['barometricPressure'])
      }
    end

    # --- Unit conversion ----------------------------------------------------

    def to_fahrenheit(measurement)
      value = measurement&.dig('value')
      return nil if value.nil?

      measurement['unitCode'].to_s.include?('degF') ? value.round : ((value * 9.0 / 5) + 32).round
    end

    def to_mph(measurement)
      value = measurement&.dig('value')
      return nil if value.nil?

      case measurement['unitCode'].to_s
      when /km_h/ then (value * 0.621371).round
      when /m_s/ then (value * 2.23694).round
      else value.round
      end
    end

    def to_inches_of_mercury(measurement)
      value = measurement&.dig('value')
      return nil if value.nil?

      (value / 3386.389).round(2)
    end

    def percentage(measurement)
      measurement&.dig('value')&.round
    end

    def to_compass(degrees)
      return nil if degrees.nil?

      COMPASS[((degrees.to_f / 22.5) + 0.5).floor % 16]
    end

    # --- Endpoints ----------------------------------------------------------

    def point_parameter
      format('%<lat>.4f,%<lon>.4f', lat: location.latitude, lon: location.longitude)
    end

    def point_properties
      Rails.cache.fetch("nws/point/#{point_parameter}", expires_in: POINT_TTL) do
        request { get("points/#{point_parameter}") }['properties'] || {}
      end
    end

    def observation_station
      Rails.cache.fetch("nws/station/#{point_parameter}", expires_in: STATION_TTL) do
        url = point_properties['observationStations'].presence
        next nil if url.blank?

        body = request { http(BASE_URL).get(url) { |req| req.headers['User-Agent'] = user_agent } }
        Array(body['features']).first&.dig('properties', 'stationIdentifier')
      end
    end

    def get(path, params = {})
      http(BASE_URL).get(path, params) do |request|
        request.headers['User-Agent'] = user_agent
        request.headers['Accept'] = 'application/geo+json'
      end
    end

    # NWS asks for an app name and a way to reach its operator; anonymous
    # traffic gets throttled or blocked.
    def user_agent
      ENV.fetch('NWS_USER_AGENT', 'smashboard (weather panel)')
    end
  end
end

# frozen_string_literal: true

module Weather
  # Resolves the point the forecast is for.
  #
  # NWS works in latitude/longitude and has no notion of a postal code, so a zip
  # is geocoded once and cached for a long time — zip centroids don't move.
  # An explicit lat/lon on the connection skips the lookup entirely.
  class Location
    Result = Struct.new(:latitude, :longitude, :label, keyword_init: true)

    GEOCODER_URL = 'https://api.zippopotam.us/us/'
    CACHE_TTL = 90.days
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    def self.for(...)
      new(...).call
    end

    def initialize(connection)
      @connection = connection
    end

    def call
      explicit_point || geocoded_point || raise(
        Integrations::Base::Unavailable,
        'no location set — add a postal code to your profile or coordinates to this connection'
      )
    end

    private

    def setting(key)
      @connection.settings[key].to_s.strip.presence
    end

    def explicit_point
      latitude = setting('latitude')
      longitude = setting('longitude')
      return nil if latitude.blank? || longitude.blank?

      Result.new(latitude: latitude.to_f, longitude: longitude.to_f, label: setting('label') || 'Your location')
    end

    def geocoded_point
      postal_code = setting('postal_code') || @connection.user.postal_code.presence
      return nil if postal_code.blank?

      Rails.cache.fetch("weather/location/#{postal_code}", expires_in: CACHE_TTL) { geocode(postal_code) }
    end

    def geocode(postal_code)
      response = http.get("#{GEOCODER_URL}#{CGI.escape(postal_code)}")

      unless response.status == 200
        raise Integrations::Base::Unavailable, "could not look up postal code #{postal_code}"
      end

      place = Array(response.body['places']).first
      raise Integrations::Base::Unavailable, "no such postal code: #{postal_code}" if place.blank?

      Result.new(
        latitude: place['latitude'].to_f,
        longitude: place['longitude'].to_f,
        label: [place['place name'], place['state abbreviation']].compact_blank.join(', ')
      )
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      raise Integrations::Base::Unavailable, "postal code lookup failed: #{e.message}"
    end

    def http
      Faraday.new do |f|
        f.response :json, content_type: /\bjson/
        f.options.open_timeout = OPEN_TIMEOUT
        f.options.timeout = READ_TIMEOUT
      end
    end
  end
end

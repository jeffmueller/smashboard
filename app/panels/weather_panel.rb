# frozen_string_literal: true

# Current conditions and active NWS alerts, with a radar loop.
#
# Payload contract:
#   { location:, conditions: { temperature_f:, humidity:, wind_mph:, ... },
#     alerts: [{ id:, event:, severity:, headline:, area:, description:,
#                starts_at:, ends_at:, sender: }],
#     radar_url:, partial: }
class WeatherPanel < ApplicationPanel
  # Which client speaks to which brand of personal weather station. The vendor
  # is a connection setting so a second brand is a class, not a rewrite.
  STATION_CLIENTS = { 'tempest' => Integrations::Tempest }.freeze
  DEFAULT_VENDOR = 'tempest'

  class << self
    def title = 'Weather'
    def description = 'Conditions and active NWS alerts for your area'
    def required_providers = %w[nws weather_station]
    def refresh_interval = 10.minutes
    def default_col_span = 2
  end

  def fetch
    results, partial = across_connections do |connection|
      connection.provider == 'nws' ? from_nws(connection) : from_station(connection)
    end

    combine(results, partial)
  end

  # Weather alerts are the one notification worth interrupting someone for, so
  # this fires on anything at or above the severity they chose.
  def notify(previous_data)
    already_seen = Array(previous_data[:alerts]).to_set { |alert| alert[:id] }
    threshold = Integrations::Nws.severity_rank(minimum_severity)

    Array(cached_data[:alerts]).each do |alert|
      next if already_seen.include?(alert[:id])
      next if Integrations::Nws.severity_rank(alert[:severity]) < threshold

      announce_alert(alert)
    end
  end

  private

  def from_nws(connection)
    client = Integrations::Nws.new(connection)

    {
      source: 'nws',
      location: client.location.label,
      alerts: client.alerts,
      conditions: client.conditions,
      radar_url: (client.radar_url if show_radar?)
    }
  end

  def from_station(connection)
    vendor = connection.settings['vendor'].presence || DEFAULT_VENDOR
    client = STATION_CLIENTS[vendor]
    raise Integrations::Base::Unavailable, "unsupported weather station: #{vendor}" if client.nil?

    { source: 'station', conditions: client.new(connection).conditions }
  end

  def combine(results, partial)
    from_nws_sources = results.select { |result| result[:source] == 'nws' }
    from_stations = results.select { |result| result[:source] == 'station' }

    alerts = from_nws_sources.flat_map { |result| Array(result[:alerts]) }
                             .uniq { |alert| alert[:id] }
                             .sort_by { |alert| -Integrations::Nws.severity_rank(alert[:severity]) }

    {
      location: from_nws_sources.filter_map { |result| result[:location] }.first,
      # A station in your own garden beats the airport twenty miles away, so it
      # wins when both are connected.
      conditions: pick_conditions(from_stations, from_nws_sources),
      alerts: alerts,
      radar_url: from_nws_sources.filter_map { |result| result[:radar_url] }.first,
      partial: partial
    }
  end

  def pick_conditions(from_stations, from_nws_sources)
    from_stations.filter_map { |result| result[:conditions] }.first ||
      from_nws_sources.filter_map { |result| result[:conditions] }.first
  end

  def announce_alert(alert)
    Notifications::Deliver.call(
      user,
      'weather_alert',
      Notifications::Deliver::Payload.new(
        title: alert[:event].presence || 'Weather alert',
        body: (alert[:headline].presence || alert[:area]).to_s.truncate(180),
        url: '/',
        tag: "weather-#{alert[:id]}",
        # A severe-weather warning should stay on screen until acknowledged.
        require_interaction: true
      ),
      dedupe_key: alert[:id].to_s
    )
  end

  def minimum_severity
    NotificationPreference.resolve(user, 'weather_alert').setting('minimum_severity') || 'severe'
  end

  def show_radar?
    ActiveModel::Type::Boolean.new.cast(settings.fetch('show_radar', true))
  end
end

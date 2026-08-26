# frozen_string_literal: true

# Claude Code usage, as reported by the machines you actually run it on.
#
# A local panel with no integration: the numbers live where the agent runs —
# rate limits behind that machine's OAuth login, token counts in its local
# transcripts — and the server can reach none of it. Each machine collects and
# pushes to /api/v1/agent_usage; this reads the latest snapshot from each.
#
# Payload contract:
#   { ready:, tier:, limits: [{ label:, percent:, resets_at:, resets_label: }],
#     today_tokens:, today_by_model: [{ model:, tokens: }], today_prompts:,
#     today_sessions:, recent_days: [{ date:, tokens: }],
#     machines: [{ name:, reported_at:, stale:, today_tokens: }],
#     stale:, message: }
class ClaudeUsagePanel < ApplicationPanel
  AGENT = 'claude'
  RECENT_DAYS = 7

  class << self
    def title = 'Claude Usage'
    def description = 'Claude Code limits and token usage from your machines'
    def default_col_span = 2
  end

  def build
    reports = user.agent_usage_reports.where(agent: AGENT).ordered.to_a
    return empty_payload if reports.empty?

    freshest = reports.min_by { |report| report.stale? ? 1 : 0 }

    {
      ready: reports.any? { |report| truthy?(payload_of(report)['ready']) },
      tier: payload_of(freshest)['tierLabel'].presence,
      # Limits are account-wide rather than per machine, so they come from one
      # report — the freshest — instead of being summed into nonsense.
      limits: limits_from(freshest),
      today_tokens: sum_across(reports, 'todayTotalTokens'),
      today_by_model: today_by_model(reports),
      today_prompts: sum_across(reports, 'todayPrompts'),
      today_sessions: sum_across(reports, 'todaySessions'),
      recent_days: recent_days(reports),
      machines: reports.map { |report| machine_row(report) },
      stale: reports.all?(&:stale?),
      message: payload_of(freshest)['usageStatusText'].presence
    }
  end

  private

  def empty_payload
    {
      ready: false, tier: nil, limits: [], today_tokens: 0, today_by_model: [],
      today_prompts: 0, today_sessions: 0, recent_days: [], machines: [], stale: true,
      message: 'No machine has reported yet. See script/smashboard-usage-reporter.'
    }
  end

  def payload_of(report)
    report&.payload.is_a?(Hash) ? report.payload : {}
  end

  # JSON round-trips booleans faithfully, but a collector that emits "true"
  # shouldn't silently read as false.
  def truthy?(value)
    ActiveModel::Type::Boolean.new.cast(value) || false
  end

  def limits_from(report)
    Array(payload_of(report)['limits']).filter_map do |limit|
      label = limit['label'].presence || limit['title'].presence
      next if label.blank?

      resets_at = parse_time(limit['resetsAt'])
      { label: label, percent: limit['percent'].to_f.clamp(0, 1),
        resets_at: resets_at&.iso8601, resets_label: resets_label(resets_at) }
    end
  end

  def resets_label(time)
    return nil if time.nil? || time <= Time.current

    "resets in #{ActionController::Base.helpers.distance_of_time_in_words(Time.current, time)}"
  end

  def sum_across(reports, key)
    reports.sum { |report| payload_of(report)[key].to_i }
  end

  def today_by_model(reports)
    totals = reports.each_with_object(Hash.new(0)) do |report, acc|
      by_model = payload_of(report)['todayTokensByModel']
      next unless by_model.is_a?(Hash)

      by_model.each { |model, tokens| acc[model] += tokens.to_i }
    end

    totals.sort_by { |_model, tokens| -tokens }.map { |model, tokens| { model: model, tokens: tokens } }
  end

  # The collector's recentDays carries a token total under `messageCount`,
  # which is its own historical misnomer rather than a count of messages.
  def recent_days(reports)
    totals = Hash.new(0)

    reports.each do |report|
      Array(payload_of(report)['recentDays']).each do |day|
        date = day['date'].to_s
        totals[date] += day['messageCount'].to_i if date.present?
      end
    end

    totals.sort_by { |date, _| date }.last(RECENT_DAYS).map { |date, tokens| { date: date, tokens: tokens } }
  end

  def machine_row(report)
    {
      name: report.machine,
      reported_at: report.reported_at.iso8601,
      stale: report.stale?,
      today_tokens: payload_of(report)['todayTotalTokens'].to_i
    }
  end

  def parse_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end

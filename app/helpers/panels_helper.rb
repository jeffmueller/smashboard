# frozen_string_literal: true

module PanelsHelper
  # Tailwind only ships classes it can see in source, so spans are mapped to
  # literal class names here rather than interpolated at render time.
  COL_SPANS = {
    1 => 'lg:col-span-1',
    2 => 'lg:col-span-2',
    3 => 'lg:col-span-3',
    4 => 'lg:col-span-4'
  }.freeze

  ROW_SPANS = {
    1 => 'row-span-1',
    2 => 'row-span-2',
    3 => 'row-span-3',
    4 => 'row-span-4'
  }.freeze

  ACCENTS = {
    'sky' => 'text-accent border-accent/40 bg-accent/10',
    'emerald' => 'text-ok border-ok/40 bg-ok/10',
    'amber' => 'text-warn border-warn/40 bg-warn/10',
    'rose' => 'text-danger border-danger/40 bg-danger/10',
    'violet' => 'text-info border-info/40 bg-info/10',
    'slate' => 'text-ink-muted border-line bg-raised'
  }.freeze

  # NWS CAP severities, loudest first.
  ALERT_SEVERITIES = {
    'extreme' => 'border-danger/60 bg-danger/15 text-danger',
    'severe' => 'border-danger/40 bg-danger/10 text-danger',
    'moderate' => 'border-warn/40 bg-warn/10 text-warn',
    'minor' => 'border-accent/40 bg-accent/10 text-accent',
    'unknown' => 'border-line bg-raised/60 text-ink-muted'
  }.freeze

  def alert_classes(severity)
    ALERT_SEVERITIES.fetch(severity.to_s.downcase, ALERT_SEVERITIES['unknown'])
  end

  def panel_span_classes(panel)
    [COL_SPANS.fetch(panel.col_span, COL_SPANS[1]), ROW_SPANS.fetch(panel.row_span, ROW_SPANS[1])].join(' ')
  end

  def accent_classes(color)
    ACCENTS.fetch(color.to_s, ACCENTS['slate'])
  end

  # Local panels read straight from the database on every render, so there's no
  # freshness to report and the header stays quiet.
  def panel_status_label(panel)
    return nil unless panel.presenter.class.remote?
    return 'Not built yet' if panel.presenter.class.pending?
    return 'Needs setup' unless panel.presenter.configured?
    return 'Error' if panel.data_status == 'error'
    return "Updated #{time_ago_in_words(panel.data_fetched_at)} ago" if panel.data_fetched_at

    'Waiting'
  end
end

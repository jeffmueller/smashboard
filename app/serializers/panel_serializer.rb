# frozen_string_literal: true

# The wire format for a panel, shared by the JSON API and any future native
# client. `data` is whatever the panel's presenter renders, so the API and the
# web dashboard can never drift apart.
class PanelSerializer
  def initialize(panel)
    @panel = panel
  end

  def as_json(*)
    {
      id: @panel.id,
      kind: @panel.kind,
      title: @panel.display_title,
      position: @panel.position,
      col_span: @panel.col_span,
      row_span: @panel.row_span,
      enabled: @panel.enabled,
      status: @panel.data_status,
      stale: @panel.stale?,
      pending: @panel.presenter.class.pending?,
      configured: @panel.presenter.configured?,
      fetched_at: @panel.data_fetched_at&.iso8601,
      last_error: @panel.last_error,
      settings: @panel.settings,
      data: @panel.presenter.view_data
    }
  end
end

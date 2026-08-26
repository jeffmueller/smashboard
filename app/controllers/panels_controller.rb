# frozen_string_literal: true

class PanelsController < ApplicationController
  before_action :set_panel, only: %i[update destroy refresh]

  def create
    # Resolved by looking the kind up among the known panel classes rather than
    # by interpolating it into a constant name: a parameter never reaches
    # `safe_constantize`, so there is no autoload to reason about, and
    # ApplicationPanel.all is already the list of what exists.
    kind = params[:kind].to_s
    panel_class = ApplicationPanel.all.find { |klass| klass.kind == kind }
    return head :unprocessable_content if panel_class.nil? || Panel::KINDS.exclude?(kind)

    panel = current_user.panels.create!(
      kind: kind,
      position: current_user.panels.next_position,
      col_span: panel_class.default_col_span,
      row_span: panel_class.default_row_span
    )
    redirect_to root_path, notice: "Added #{panel.display_title}."
  end

  def update
    return head :unprocessable_content unless @panel.update(panel_params)

    respond_to do |format|
      format.turbo_stream { render_layout_change }
      format.html { redirect_to root_path }
    end
  end

  def destroy
    @panel.destroy!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@panel.to_stream_target) }
      format.html { redirect_to root_path }
    end
  end

  # Accepts the full ordered list of panel ids after a drag-and-drop.
  def reorder
    if current_user.panels.apply_order(params[:panel_ids])
      head :no_content
    else
      head :unprocessable_content
    end
  end

  def refresh
    @panel.presenter.refresh!
    render turbo_stream: turbo_stream.replace(@panel.to_stream_target, partial: 'panels/panel',
                                                                       locals: { panel: @panel })
  end

  private

  # Hiding removes the tile and refreshes the hidden strip. A resize redraws the
  # tile in place. Un-hiding has to reload: the tile is not in the DOM to
  # replace, and where it belongs depends on its position among the others.
  def render_layout_change
    return render turbo_stream: tuck_away(@panel) unless @panel.enabled?
    return redirect_to root_path if @panel.previous_changes.key?('enabled')

    render turbo_stream: redraw(@panel)
  end

  def redraw(panel)
    [turbo_stream.replace(panel.to_stream_target, partial: 'panels/panel', locals: { panel: panel }),
     hidden_strip]
  end

  def tuck_away(panel)
    [turbo_stream.remove(panel.to_stream_target), hidden_strip]
  end

  def hidden_strip
    turbo_stream.replace('hidden-panels', partial: 'dashboard/hidden',
                                          locals: { panels: current_user.panels.where(enabled: false).ordered })
  end

  def set_panel
    @panel = current_user.panels.find(params.expect(:id))
  end

  def panel_params
    params.expect(panel: [:title, :enabled, :size, :col_span, :row_span, { settings: {} }])
  end
end

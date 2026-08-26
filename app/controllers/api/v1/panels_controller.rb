# frozen_string_literal: true

module Api
  module V1
    class PanelsController < BaseController
      before_action :set_panel, only: %i[show update destroy refresh]

      def index
        render json: { panels: current_user.panels.ordered.map { |p| PanelSerializer.new(p).as_json } }
      end

      def show
        render json: PanelSerializer.new(@panel).as_json
      end

      def update
        @panel.update!(panel_params)
        render json: PanelSerializer.new(@panel).as_json
      end

      def destroy
        @panel.destroy!
        head :no_content
      end

      def reorder
        return head :unprocessable_content unless current_user.panels.apply_order(params[:panel_ids])

        render json: { panels: current_user.panels.ordered.map { |p| PanelSerializer.new(p).as_json } }
      end

      def refresh
        @panel.presenter.refresh!
        render json: PanelSerializer.new(@panel.reload).as_json
      end

      private

      def set_panel
        @panel = current_user.panels.find(params.expect(:id))
      end

      def panel_params
        params.expect(panel: [:title, :enabled, :col_span, :row_span, { settings: {} }])
      end
    end
  end
end

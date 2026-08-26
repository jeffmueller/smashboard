# frozen_string_literal: true

module Api
  module V1
    # Receives usage snapshots pushed by the machines running a coding agent.
    #
    # There is no matching fetch: the server cannot reach this data on its own,
    # which is the whole reason the flow is inverted.
    class AgentUsageController < BaseController
      def index
        render json: {
          reports: current_user.agent_usage_reports.ordered.map { |r| AgentUsageReportSerializer.new(r).as_json }
        }
      end

      def create
        report = AgentUsageReport.record!(
          user: current_user,
          agent: params[:agent].to_s,
          machine: params[:machine].to_s,
          payload: payload,
          reported_at: reported_at
        )

        render json: AgentUsageReportSerializer.new(report).as_json, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_content
      end

      def destroy
        report = current_user.agent_usage_reports.find(params.expect(:id))
        report.destroy!
        head :no_content
      end

      private

      # The payload is whatever the collector produced. It is stored verbatim
      # and only ever read by key, never executed or interpolated, so it is not
      # filtered through strong parameters.
      def payload
        raw = params[:payload]
        return {} unless raw.respond_to?(:to_unsafe_h) || raw.is_a?(Hash)

        (raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw).to_h
      end

      # The reporter says when it collected; a missing or unparseable time means
      # now, which is near enough and better than refusing the push.
      def reported_at
        Time.zone.parse(params[:reported_at].to_s) || Time.current
      rescue ArgumentError, TypeError
        Time.current
      end
    end
  end
end

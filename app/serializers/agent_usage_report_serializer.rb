# frozen_string_literal: true

class AgentUsageReportSerializer
  def initialize(report)
    @report = report
  end

  def as_json(*)
    {
      id: @report.id,
      agent: @report.agent,
      machine: @report.machine,
      reported_at: @report.reported_at.iso8601,
      stale: @report.stale?,
      payload: @report.payload
    }
  end
end

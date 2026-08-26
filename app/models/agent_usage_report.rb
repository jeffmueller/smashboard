# frozen_string_literal: true

# The latest usage snapshot pushed by one machine running a coding agent.
#
# Pushed rather than fetched: the numbers live on the machine the agent runs on
# — rate limits behind that machine's OAuth login, token counts in its local
# transcripts — and none of it is reachable from the server. So the machine
# collects and posts, and the credential never leaves it.
class AgentUsageReport < ApplicationRecord
  AGENTS = %w[claude].freeze

  # Older than this and the machine is presumed asleep or switched off, so its
  # numbers are shown as stale rather than as current.
  STALE_AFTER = 30.minutes

  belongs_to :user

  validates :agent, inclusion: { in: AGENTS }
  validates :machine, presence: true, length: { maximum: 120 }
  validates :reported_at, presence: true
  validates :machine, uniqueness: { scope: %i[user_id agent] }

  scope :ordered, -> { order(reported_at: :desc) }

  # Records the snapshot for a machine, replacing whatever it sent last.
  def self.record!(user:, agent:, machine:, payload:, reported_at: Time.current)
    report = find_or_initialize_by(user: user, agent: agent, machine: machine)
    report.update!(payload: payload, reported_at: reported_at)
    report
  end

  def stale?
    reported_at < STALE_AFTER.ago
  end
end

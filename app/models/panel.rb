# frozen_string_literal: true

# One tile on a user's dashboard. `data` caches the last successful remote
# fetch so rendering the dashboard never blocks on a third-party API.
class Panel < ApplicationRecord
  include Positioned

  KINDS = %w[
    clock
    countdowns
    todos
    habits
    bookmarks
    email
    calendar
    github_notifications
    github_pull_requests
    slack
    news
    weather
    cameras
    claude_usage
  ].freeze

  DATA_STATUSES = %w[idle refreshing ok error].freeze

  # Named widths rather than a free resize: the dashboard is a four-column grid,
  # so these are the only values that tile without leaving a ragged gap.
  SIZES = { 'small' => 1, 'medium' => 2, 'large' => 3, 'full' => 4 }.freeze

  belongs_to :user

  validates :kind, inclusion: { in: KINDS }
  validates :data_status, inclusion: { in: DATA_STATUSES }
  validates :col_span, :row_span, numericality: { in: 1..4 }

  scope :enabled, -> { where(enabled: true) }

  def size
    SIZES.key(col_span) || 'medium'
  end

  def size=(value)
    self.col_span = SIZES.fetch(value.to_s, col_span)
  end

  def presenter
    @presenter ||= ApplicationPanel.for(self)
  end

  def display_title
    title.presence || presenter.class.title
  end

  def stale?
    return false unless presenter.class.remote?
    return true if data_fetched_at.blank?

    data_fetched_at < presenter.class.refresh_interval.ago
  end

  def refresh_later
    RefreshPanelJob.perform_later(id)
  end

  def to_stream_target
    ActionView::RecordIdentifier.dom_id(self)
  end
end

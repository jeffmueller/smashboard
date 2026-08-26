# frozen_string_literal: true

# Per-user, per-kind notification switches. A missing row means "use the
# default for that kind", so a new notification type doesn't require a
# backfill before it can fire.
class NotificationPreference < ApplicationRecord
  KINDS = {
    'weather_alert' => { via_web_push: true, via_email: false, settings: { 'minimum_severity' => 'severe' } },
    'breaking_news' => { via_web_push: true, via_email: false, settings: {} },
    'meeting_reminder' => { via_web_push: true, via_email: false, settings: { 'lead_minutes' => 10 } },
    'countdown_reached' => { via_web_push: true, via_email: false, settings: { 'lead_minutes' => 0 } },
    'email_received' => { via_web_push: false, via_email: false, settings: {} },
    'github_review_requested' => { via_web_push: true, via_email: false, settings: {} },
    'connection_failing' => { via_web_push: true, via_email: true, settings: {} }
  }.freeze

  # Presentation and editable per-kind settings, kept separate from KINDS
  # because KINDS is splatted into `new` as attributes.
  METADATA = {
    'meeting_reminder' => {
      requires_panel: 'calendar',
      label: 'Meeting reminders',
      description: 'Ahead of each meeting on your calendar, with a link to join the call.',
      fields: [{ key: 'lead_minutes', label: 'Minutes before', type: :integer }]
    },
    'countdown_reached' => {
      label: 'Countdowns',
      description: 'When a countdown reaches its moment.',
      fields: [{ key: 'lead_minutes', label: 'Minutes before', type: :integer }]
    },
    'breaking_news' => {
      requires_panel: 'news',
      label: 'Breaking news',
      description: 'When the top story on your news feed changes.',
      fields: []
    },
    'weather_alert' => {
      requires_panel: 'weather',
      label: 'Weather alerts',
      description: 'Active alerts issued by the NWS for your area.',
      fields: [{ key: 'minimum_severity', label: 'At least', type: :select,
                 options: %w[extreme severe moderate minor] }]
    },
    'github_review_requested' => {
      requires_panel: 'github_pull_requests',
      label: 'Review requests',
      description: 'When someone asks you to review a pull request.',
      fields: []
    },
    'email_received' => {
      requires_panel: 'email',
      label: 'New email',
      description: 'When a message arrives in a connected mailbox.',
      fields: []
    },
    'connection_failing' => {
      label: 'Connection problems',
      description: 'When a connected account stops working. At most one a day per account.',
      fields: []
    }
  }.freeze

  belongs_to :user

  validates :kind, inclusion: { in: KINDS.keys }, uniqueness: { scope: :user_id }

  scope :enabled, -> { where(enabled: true) }

  def self.defaults_for(kind)
    KINDS.fetch(kind)
  end

  # Resolves a user's setting for a kind, falling back to the shipped default
  # when they've never touched it.
  def self.resolve(user, kind)
    find_by(user: user, kind: kind) || new(user: user, kind: kind, **defaults_for(kind))
  end

  def self.metadata_for(kind)
    METADATA.fetch(kind, { label: kind.humanize, description: '', fields: [] })
  end

  # Every kind, resolved for this user, in a stable order for the settings form.
  def self.all_for(user)
    KINDS.keys.map { |kind| resolve(user, kind) }
  end

  def label
    self.class.metadata_for(kind)[:label]
  end

  def description
    self.class.metadata_for(kind)[:description]
  end

  def fields
    self.class.metadata_for(kind)[:fields]
  end

  # A notification kind is only live once the panel that produces it exists.
  # Offering a switch for something that cannot fire is worse than hiding it.
  def available?
    panel_kind = self.class.metadata_for(kind)[:requires_panel]
    return true if panel_kind.blank?

    klass = "#{panel_kind.camelize}Panel".safe_constantize
    klass.present? && !klass.pending?
  end

  def setting(key)
    settings.fetch(key.to_s) { self.class.defaults_for(kind)[:settings][key.to_s] }
  end

  def deliver_via
    [].tap do |channels|
      channels << :web_push if via_web_push?
      channels << :email if via_email?
    end
  end
end

# frozen_string_literal: true

class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable

  has_many :connections, dependent: :destroy
  has_many :panels, dependent: :destroy
  has_many :countdowns, dependent: :destroy
  has_many :todos, dependent: :destroy
  has_many :todo_projects, dependent: :destroy
  has_many :bookmarks, dependent: :destroy
  has_many :habits, dependent: :destroy
  has_many :agent_usage_reports, dependent: :destroy
  has_many :api_tokens, dependent: :destroy
  has_many :push_subscriptions, dependent: :destroy
  has_many :notification_preferences, dependent: :destroy
  has_many :notification_deliveries, dependent: :destroy

  validates :first_name, :last_name, length: { maximum: 80 }
  validates :time_zone, inclusion: { in: ActiveSupport::TimeZone.all.map(&:name) }
  validates :postal_code, format: { with: /\A\d{5}(-\d{4})?\z/, allow_blank: true }
  validates :theme, inclusion: { in: ->(_) { Theme.slugs + [Theme::SYSTEM] } }, allow_blank: true

  after_create_commit :install_default_dashboard

  # Nil renders no data-theme attribute, leaving the stylesheet's
  # prefers-color-scheme block in charge.
  def theme_attribute
    Theme.attribute_for(theme)
  end

  def resolved_theme
    Theme.find(theme) || Theme.find(Theme::SYSTEM_DARK) || Theme.fallback
  end

  def zone
    ActiveSupport::TimeZone[time_zone] || Time.zone
  end

  # "Today" is the user's today, not the server's.
  delegate :today, to: :zone

  def full_name
    [first_name, last_name].compact_blank.join(' ').presence
  end

  # What the dashboard greets you with — a given name if there is one, and the
  # local part of the email as a last resort.
  def display_name
    first_name.presence || full_name || email.split('@').first
  end

  private

  def install_default_dashboard
    Dashboards::InstallDefaults.new(self).call
  end
end

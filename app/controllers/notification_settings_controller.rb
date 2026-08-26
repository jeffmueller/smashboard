# frozen_string_literal: true

class NotificationSettingsController < ApplicationController
  # Permitted per kind rather than with `permit!`. Nothing was ever mass-assigned
  # — #update names the four attributes and cleaned_settings slices the rest —
  # but spelling the shape out means a reader (and Brakeman) can see that from
  # here instead of having to trace it.
  PERMITTED_PER_KIND = [:enabled, :via_web_push, :via_email, { settings: {} }].freeze

  def show
    @preferences = NotificationPreference.all_for(current_user)
  end

  def update
    NotificationPreference.transaction do
      submitted.each do |kind, attributes|
        next unless NotificationPreference::KINDS.key?(kind)

        preference = current_user.notification_preferences.find_or_initialize_by(kind: kind)
        preference.assign_attributes(
          enabled: boolean(attributes[:enabled]),
          via_web_push: boolean(attributes[:via_web_push]),
          via_email: boolean(attributes[:via_email]),
          settings: cleaned_settings(kind, attributes[:settings])
        )
        preference.save!
      end
    end

    redirect_to notification_settings_path, notice: 'Notification settings saved.'
  end

  private

  def submitted
    params.fetch(:notification_preferences, {})
          .permit(NotificationPreference::KINDS.keys.index_with { PERMITTED_PER_KIND })
          .to_h
  end

  def boolean(value)
    ActiveModel::Type::Boolean.new.cast(value) || false
  end

  # Only keep keys the kind actually declares, so a hand-crafted form post can't
  # stuff arbitrary data into the settings blob.
  def cleaned_settings(kind, submitted_settings)
    allowed = NotificationPreference.metadata_for(kind)[:fields].pluck(:key)
    Hash(submitted_settings).slice(*allowed).compact_blank
  end
end

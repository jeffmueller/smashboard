# frozen_string_literal: true

class AppearancesController < ApplicationController
  def show
    @themes = Theme.all
    @selected = current_user.theme.presence || Theme::SYSTEM
  end

  def update
    if current_user.update(theme: theme_param)
      redirect_to appearance_path, notice: 'Theme saved.'
    else
      @themes = Theme.all
      @selected = current_user.theme.presence || Theme::SYSTEM
      render :show, status: :unprocessable_content
    end
  end

  private

  # An unknown slug is rejected by the model, but normalising "system" to nil
  # here keeps the stored value meaning exactly one thing: nil follows the OS.
  def theme_param
    value = params.expect(user: [:theme])[:theme].to_s
    value == Theme::SYSTEM ? nil : value
  end
end

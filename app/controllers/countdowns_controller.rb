# frozen_string_literal: true

class CountdownsController < ApplicationController
  before_action :set_countdown, only: %i[edit update destroy dismiss]

  def index
    @countdowns = current_user.countdowns.ordered
  end

  def new
    @countdown = current_user.countdowns.new(color: 'sky')
  end

  def edit; end

  def create
    @countdown = current_user.countdowns.new(countdown_params)

    if @countdown.save
      redirect_to countdowns_path, notice: "#{@countdown.name} is counting down."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @countdown.update(countdown_params)
      redirect_to countdowns_path, notice: "#{@countdown.name} updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @countdown.destroy!
    redirect_to countdowns_path, notice: "#{@countdown.name} deleted."
  end

  # Waves off a single occurrence. A recurring countdown reappears on its next
  # iteration; a one-off goes quiet for good. The confirmation lives in the UI.
  def dismiss
    occurrence_at = Time.iso8601(params.require(:occurrence_at))
    @countdown.dismiss!(occurrence_at)

    respond_to do |format|
      format.turbo_stream { render turbo_stream: refreshed_countdowns_panel }
      format.html { redirect_to root_path }
      format.json { head :no_content }
    end
  rescue ArgumentError, ActionController::ParameterMissing
    head :bad_request
  end

  private

  def set_countdown
    @countdown = current_user.countdowns.find(params.expect(:id))
  end

  def refreshed_countdowns_panel
    panel = current_user.panels.find_by(kind: 'countdowns')
    return turbo_stream.replace('flash', partial: 'shared/flash') if panel.nil?

    turbo_stream.replace(panel.to_stream_target, partial: 'panels/panel', locals: { panel: panel })
  end

  def countdown_params
    params.expect(countdown: %i[name description color target_at rrule starts_on occurs_at_time time_zone enabled
                                position])
  end
end

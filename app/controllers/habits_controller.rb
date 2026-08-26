# frozen_string_literal: true

class HabitsController < ApplicationController
  before_action :set_habit, only: %i[update destroy toggle archive unarchive]

  def index
    @habits = current_user.habits.active.ordered
    @archived = current_user.habits.archived.ordered
    @habit = current_user.habits.new
  end

  def create
    @habit = current_user.habits.new(habit_params)
    @habit.position = current_user.habits.next_position

    if @habit.save
      respond_to do |format|
        format.turbo_stream { render turbo_stream: refreshed_views }
        format.html { redirect_back_or_to(habits_path) }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: reported_error, status: :unprocessable_content }
        format.html { render_index_with_errors }
      end
    end
  end

  def update
    if @habit.update(habit_params)
      redirect_to habits_path
    else
      render_index_with_errors
    end
  end

  def destroy
    @habit.destroy!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: refreshed_views }
      format.html { redirect_to habits_path }
    end
  end

  # Checking off is a toggle rather than separate complete/uncomplete actions:
  # the tile is one control, and tapping it twice should land back where it
  # started rather than erroring.
  def toggle
    @habit.toggle_completion!(today)

    respond_to do |format|
      format.turbo_stream { render turbo_stream: refreshed_views }
      format.html { redirect_back_or_to(root_path) }
    end
  end

  # Retiring keeps the history so the graph doesn't lose its past.
  def archive
    @habit.archive!
    redirect_to habits_path, notice: "Archived #{@habit.name}."
  end

  def unarchive
    @habit.unarchive!
    redirect_to habits_path, notice: "Restored #{@habit.name}."
  end

  def reorder
    if current_user.habits.apply_order(params[:habit_ids])
      head :no_content
    else
      head :unprocessable_content
    end
  end

  private

  def set_habit
    @habit = current_user.habits.find(params.expect(:id))
  end

  # The user's day, not the server's — an around_action already puts the
  # request in their zone.
  def today
    Time.zone.today
  end

  # Habits are edited from the board and from this page, and a Turbo Stream
  # aimed at an element the current page doesn't have is ignored — so one
  # response carries both and whichever page is open takes what it has.
  def refreshed_views
    [panel_stream, list_stream, form_stream, flash_stream].compact
  end

  def reported_error
    flash.now[:alert] = @habit.errors.full_messages.to_sentence
    [flash_stream]
  end

  def panel_stream
    panel = current_user.panels.find_by(kind: 'habits')
    return nil if panel.nil?

    turbo_stream.replace(panel.to_stream_target, partial: 'panels/panel', locals: { panel: panel })
  end

  def list_stream
    turbo_stream.replace('habits-list', partial: 'habits/list',
                                        locals: { habits: current_user.habits.active.ordered,
                                                  archived: current_user.habits.archived.ordered })
  end

  def form_stream
    turbo_stream.replace('new-habit', partial: 'habits/new_form',
                                      locals: { habit: current_user.habits.new })
  end

  def flash_stream
    turbo_stream.replace('flash', partial: 'shared/flash')
  end

  def render_index_with_errors
    @habits = current_user.habits.active.ordered
    @archived = current_user.habits.archived.ordered
    render :index, status: :unprocessable_content
  end

  def habit_params
    params.expect(habit: %i[name icon])
  end
end
